//
//  WatchNowPlayingView.swift
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

import SwiftUI

/// Compact player modeled after the iOS full player: artwork + titles on one row,
/// progress with remaining time, transport controls, and a secondary row for
/// seeking, download, and the queue. The Digital Crown sets the volume (the watch
/// equivalent of the iOS volume slider) and flashes a small HUD while turning.
struct WatchNowPlayingView: View {
  @ObservedObject
  private var player = WatchPlayerService.shared
  @State
  private var isDownloaded = false
  @State
  private var pendingDownload = false
  @State
  private var isQueuePresented = false
  @State
  private var crownVolume = 1.0
  @State
  private var isVolumeHudVisible = false
  @State
  private var volumeHudHideTask: Task<Void, Never>?
  @FocusState
  private var isVolumeControlFocused: Bool

  var body: some View {
    Group {
      if let song = player.currentSong {
        VStack(spacing: 10) {
          Spacer(minLength: 0)

          // Title row
          HStack(spacing: 8) {
            WatchArtworkView(artworkId: song.artworkId, size: 44)
            VStack(alignment: .leading, spacing: 2) {
              Text(song.title).font(.headline).lineLimit(1)
              Text(song.artistName).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
          }

          // Progress: elapsed on the left, remaining (iOS style) on the right.
          if player.duration > 0 {
            VStack(spacing: 2) {
              ProgressView(value: player.elapsedTime, total: player.duration)
              HStack {
                Text(WatchFormatters.duration(player.elapsedTime))
                Spacer()
                Text("-\(WatchFormatters.duration(player.remainingTime))")
              }
              .font(.caption2)
              .foregroundColor(.secondary)
            }
          }

          // Transport controls
          HStack(spacing: 24) {
            Button { Task { await player.playPrevious() } } label: {
              Image(systemName: "backward.fill").font(.title3)
            }
            .buttonStyle(.plain)

            Button { Task { await player.togglePlayPause() } } label: {
              Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
            }
            .buttonStyle(.borderedProminent)

            Button { Task { await player.playNext() } } label: {
              Image(systemName: "forward.fill").font(.title3)
            }
            .buttonStyle(.plain)
          }

          // Secondary actions: seek, download, queue.
          HStack(spacing: 20) {
            Button { Task { await player.seekBackward() } } label: {
              Image(systemName: "gobackward.15")
            }
            downloadButton
            Button { Task { await player.seekForward() } } label: {
              Image(systemName: "goforward.15")
            }
            Button { isQueuePresented = true } label: {
              Image(systemName: "list.bullet")
            }
          }
          .font(.callout)
          .buttonStyle(.plain)

          Spacer(minLength: 0)
        }
        .padding(.horizontal)
      } else {
        VStack(spacing: 8) {
          Spacer()
          Image(systemName: "music.note").font(.largeTitle).foregroundColor(.secondary)
          Text("Nothing playing").foregroundColor(.secondary).font(.caption)
          Spacer()
        }
      }
    }
    .overlay(alignment: .bottom) {
      if isVolumeHudVisible {
        Label("\(Int((crownVolume * 100).rounded()))%", systemImage: "speaker.wave.2.fill")
          .font(.caption2)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(.regularMaterial, in: Capsule())
          .transition(.opacity)
      }
    }
    .focusable(true)
    .focused($isVolumeControlFocused)
    .digitalCrownRotation(
      $crownVolume,
      from: 0,
      through: 1,
      by: 0.02,
      sensitivity: .high,
      isContinuous: false,
      isHapticFeedbackEnabled: true
    )
    .onAppear {
      crownVolume = Double(player.volume)
      isVolumeControlFocused = true
    }
    .onChange(of: crownVolume) { newValue in
      player.volume = Float(newValue)
      flashVolumeHud()
    }
    .task { await refreshDownloadState() }
    .onChange(of: player.currentSong?.id) { _ in
      Task { await refreshDownloadState() }
    }
    .sheet(isPresented: $isQueuePresented) {
      WatchQueueView()
    }
  }

  @ViewBuilder
  private var downloadButton: some View {
    if pendingDownload {
      ProgressView().controlSize(.mini)
    } else {
      Button {
        Task {
          pendingDownload = true
          defer { pendingDownload = false }
          guard let song = player.currentSong else { return }
          isDownloaded = await WatchDownloadService.shared.toggleDownload(playable: song)
        }
      } label: {
        Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
          .foregroundStyle(isDownloaded ? Color.green : Color.primary)
      }
    }
  }

  private func flashVolumeHud() {
    isVolumeHudVisible = true
    volumeHudHideTask?.cancel()
    volumeHudHideTask = Task {
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      guard !Task.isCancelled else { return }
      withAnimation { isVolumeHudVisible = false }
    }
  }

  private func refreshDownloadState() async {
    guard let id = player.currentSong?.id else { isDownloaded = false; return }
    isDownloaded = await WatchDownloadService.shared.isDownloaded(playableId: id)
  }
}

// MARK: - WatchQueueView

/// Up Next: shuffle/repeat controls plus the player's queue with the current song
/// highlighted, tap to jump — the watch analog of the iOS queue screen.
struct WatchQueueView: View {
  @ObservedObject
  private var player = WatchPlayerService.shared

  var body: some View {
    ScrollViewReader { proxy in
      List {
        Section {
          Button {
            player.toggleShuffle()
          } label: {
            Label("Shuffle", systemImage: "shuffle")
              .foregroundStyle(player.isShuffleActive ? Color.accentColor : Color.primary)
          }
          Button {
            player.cycleRepeatMode()
          } label: {
            Label(player.repeatMode.displayName, systemImage: player.repeatMode.systemImage)
              .foregroundStyle(player.repeatMode != .off ? Color.accentColor : Color.primary)
          }
        }

        Section {
          if player.queueItems.isEmpty {
            Text("Queue is empty").foregroundColor(.secondary)
          } else {
            ForEach(Array(player.queueItems.enumerated()), id: \.offset) { idx, song in
              Button {
                Task { await player.playQueueItem(at: idx) }
              } label: {
                HStack(spacing: 8) {
                  WatchArtworkView(artworkId: song.artworkId, size: 30)
                  VStack(alignment: .leading, spacing: 1) {
                    Text(song.title).font(.subheadline).lineLimit(1)
                    Text(song.artistName)
                      .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                  }
                  Spacer(minLength: 4)
                  if idx == player.queueIndex {
                    Image(systemName: "waveform")
                      .font(.caption)
                      .foregroundStyle(Color.accentColor)
                  }
                }
              }
              .buttonStyle(.plain)
              .id(idx)
            }
          }
        }
      }
      .navigationTitle("Up Next")
      .onAppear { proxy.scrollTo(player.queueIndex, anchor: .center) }
    }
  }
}
