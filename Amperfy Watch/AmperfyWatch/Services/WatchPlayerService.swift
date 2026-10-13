//
//  WatchPlayerService.swift
//  Amperfy Watch
//
//  Created by Nathan Hughes on 2026-08-18.
//  Copyright © 2026 Maximilian Bauer. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import AVFoundation
import Combine
import Foundation
import MediaPlayer

/// Plays songs either by streaming from the server (AVPlayer with auth in the URL
/// and custom HTTP headers passed via the asset options) or from a downloaded file.
/// Maintains a queue for next/previous and publishes state for the Now Playing UI.
@MainActor
final class WatchPlayerService: ObservableObject {
  static let shared = WatchPlayerService()

  @Published
  private(set) var currentSong: WatchPlayableInfo?
  @Published
  private(set) var isPlaying = false
  @Published
  private(set) var elapsedTime: TimeInterval = 0
  @Published
  private(set) var duration: TimeInterval = 0
  /// The active queue and the position of `currentSong` within it. Published so the
  /// Up Next UI can list and jump to queued items.
  @Published
  private(set) var queueItems: [WatchPlayableInfo] = []
  @Published
  private(set) var queueIndex = -1
  /// Output volume, driven by the Digital Crown on the Now Playing screen.
  @Published
  var volume: Float = 1.0 {
    didSet { avPlayer?.volume = volume }
  }

  @Published
  private(set) var isShuffleActive = false
  @Published
  private(set) var repeatMode: WatchRepeatMode = .off

  var remainingTime: TimeInterval { max(duration - elapsedTime, 0) }

  private var queue: [WatchPlayableInfo] = []
  /// The queue as the caller passed it, captured while shuffle is active so
  /// disabling shuffle restores the original order.
  private var unshuffledQueue: [WatchPlayableInfo]?
  private var index = -1
  private var avPlayer: AVPlayer?
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var artworkUrl: URL?
  /// Monotonic counter bumped by every `load(at:)`; a load that is still resolving
  /// its URL when a newer load starts abandons its player setup, so rapid
  /// next/previous presses only ever build one AVPlayer.
  private var loadGeneration = 0

  private init() {
    configureAudioSession()
    setupRemoteCommands()
  }

  private func configureAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [])
      try session.setActive(true)
    } catch {
      print("Failed to configure audio session: \(error)")
    }
  }

  private func setupRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.resume() }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.pause() }
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in await self?.togglePlayPause() }
      return .success
    }
    center.nextTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in await self?.playNext() }
      return .success
    }
    center.previousTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in await self?.playPrevious() }
      return .success
    }
  }

  // MARK: - Playback

  /// Play a single song (replaces the queue).
  func playSong(_ song: WatchPlayableInfo) async {
    await play(queue: [song], startingAt: 0)
  }

  /// Play `songs` starting at `startIndex`. Used by album/playlist detail views so
  /// next/previous walk the full list. With shuffle active the chosen song plays
  /// first and the rest of the queue is shuffled, like the iOS player.
  func play(queue songs: [WatchPlayableInfo], startingAt startIndex: Int) async {
    guard !songs.isEmpty, (0 ..< songs.count).contains(startIndex) else { return }
    if isShuffleActive {
      var queueToShuffle = songs
      let chosen = queueToShuffle.remove(at: startIndex)
      queueToShuffle.shuffle()
      queue = [chosen] + queueToShuffle
      unshuffledQueue = songs
      queueItems = queue
      await load(at: 0)
    } else {
      queue = songs
      unshuffledQueue = nil
      queueItems = songs
      await load(at: startIndex)
    }
  }

  /// Jump to another song already in the queue (used by the Up Next list).
  func playQueueItem(at queuePosition: Int) async {
    await load(at: queuePosition)
  }

  /// Toggle shuffle. With a queue loaded, the current song keeps playing and the
  /// remaining songs are shuffled/restored (like the iOS player).
  func toggleShuffle() {
    isShuffleActive.toggle()
    guard queue.indices.contains(index) else { return }
    let current = queue[index]
    if isShuffleActive {
      unshuffledQueue = queue
      var rest = queue
      rest.remove(at: index)
      rest.shuffle()
      queue = [current] + rest
      index = 0
    } else if let original = unshuffledQueue {
      queue = original
      index = original.firstIndex(where: { $0.id == current.id }) ?? min(index, original.count - 1)
      unshuffledQueue = nil
    }
    queueItems = queue
    queueIndex = index
  }

  /// Cycle repeat off → all → one, mirroring the iOS player.
  func cycleRepeatMode() {
    repeatMode.cycle()
  }

  private func load(at newIndex: Int) async {
    guard queue.indices.contains(newIndex) else { return }
    loadGeneration += 1
    let generation = loadGeneration
    index = newIndex
    queueIndex = newIndex
    let song = queue[index]
    currentSong = song
    duration = song.duration
    elapsedTime = 0

    // Prefer a downloaded file (offline); otherwise stream from the server.
    // Auth is embedded in the stream URL's query string, so a plain AVURLAsset works
    // without custom HTTP headers. (watchOS has no public API to attach headers to
    // AVURLAsset, so Cloudflare-Access-protected servers can't be streamed on watch.)
    var url: URL?
    if let localURL = await WatchDownloadService.shared.getCachedFileURL(for: song.id) {
      url = localURL
    } else {
      url = try? SubsonicClient.shared.streamUrl(forPlayableId: song.id)
    }

    // A newer load superseded this one while resolving; abandon player setup.
    guard let url, generation == loadGeneration else { return }
    playItem(at: url)

    artworkUrl = (
      try? song.artworkId
        .flatMap { try SubsonicClient.shared.coverArtUrl(forArtworkId: $0) }
    )
    updateNowPlayingInfo()
  }

  private func playItem(at url: URL) {
    let item = AVPlayerItem(asset: AVURLAsset(url: url))

    // Detach the observers from the outgoing player BEFORE replacing it. Releasing
    // an AVPlayer that still has a periodic time observer registered (or releasing
    // an observer token without removeTimeObserver) is undefined behavior per
    // AVPlayer.h and crashes in practice — this was the next-button crash.
    if let timeObserver, let oldPlayer = avPlayer {
      oldPlayer.removeTimeObserver(timeObserver)
    }
    timeObserver = nil
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    endObserver = nil
    avPlayer?.pause()

    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in await self?.currentItemDidFinish() }
    }

    let player = AVPlayer(playerItem: item)
    player.volume = volume
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main
    ) { [weak self] time in
      Task { @MainActor [weak self] in self?.timeDidTick(to: time) }
    }
    avPlayer = player
    player.play()
    isPlaying = true
  }

  private func timeDidTick(to time: CMTime) {
    let seconds = time.seconds
    guard seconds.isFinite, seconds >= 0 else { return }
    elapsedTime = seconds
    if let itemDuration = avPlayer?.currentItem?.duration.seconds,
       itemDuration.isFinite, itemDuration > 0 {
      duration = itemDuration
    }
    updateNowPlayingInfo()
  }

  func togglePlayPause() async {
    if isPlaying { pause() } else { resume() }
  }

  private func resume() {
    guard avPlayer != nil else { return }
    avPlayer?.play()
    isPlaying = true
    updateNowPlayingInfo()
  }

  private func pause() {
    avPlayer?.pause()
    isPlaying = false
    updateNowPlayingInfo()
  }

  /// User pressed Next. Wraps to the queue start when Repeat All is on; on the
  /// last song with Repeat Off it does nothing and keeps playing (like Apple
  /// Music) — only the natural end of playback stops the player.
  func playNext() async {
    if queue.indices.contains(index + 1) {
      await load(at: index + 1)
    } else if repeatMode == .all, !queue.isEmpty {
      await load(at: 0)
    }
  }

  func playPrevious() async {
    guard index > 0 else { return }
    await load(at: index - 1)
  }

  /// The current song played to its end (AVPlayerItemDidPlayToEndTime). The player
  /// has already stopped by itself when the queue runs out, so just reflect that.
  private func currentItemDidFinish() async {
    switch repeatMode {
    case .one:
      await seek(to: 0)
      resume()
    case .all:
      await load(at: queue.indices.contains(index + 1) ? index + 1 : 0)
    case .off:
      if queue.indices.contains(index + 1) {
        await load(at: index + 1)
      } else {
        isPlaying = false
        updateNowPlayingInfo()
      }
    }
  }

  func seek(to time: TimeInterval) async {
    await avPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    elapsedTime = time
    updateNowPlayingInfo()
  }

  /// Skip within the current song (podcasts/audiobooks), clamped to its bounds.
  func seekForward(by seconds: TimeInterval = 15) async {
    guard currentSong != nil else { return }
    let upper = duration > 0 ? max(duration - 1, 0) : TimeInterval.greatestFiniteMagnitude
    await seek(to: min(elapsedTime + seconds, upper))
  }

  func seekBackward(by seconds: TimeInterval = 15) async {
    guard currentSong != nil else { return }
    await seek(to: max(elapsedTime - seconds, 0))
  }

  /// Play a podcast episode (single-item queue).
  func playEpisode(_ episode: WatchPodcastEpisode) async {
    let song = WatchPlayableInfo(
      id: episode.id, title: episode.title,
      artistName: "Podcast", albumName: episode.title,
      artworkId: episode.artworkId, duration: episode.duration
    )
    await playSong(song)
  }

  // MARK: - Now Playing

  private func updateNowPlayingInfo() {
    var info: [String: Any] = [:]
    if let song = currentSong {
      info[MPMediaItemPropertyTitle] = song.title
      info[MPMediaItemPropertyArtist] = song.artistName
      info[MPMediaItemPropertyAlbumTitle] = song.albumName
    }
    // Only finite values: MPNowPlayingInfoCenter rejects NaN/∞ with an exception.
    if elapsedTime.isFinite, elapsedTime >= 0 {
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
    }
    if duration.isFinite, duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? (avPlayer?.rate ?? 1) : 0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
}
