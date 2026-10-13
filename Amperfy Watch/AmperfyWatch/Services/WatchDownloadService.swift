//
//  WatchDownloadService.swift
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

import Foundation

/// Downloads songs to the watch caches directory for offline playback when the
/// phone is left behind. Downloaded songs are played from local file by
/// `WatchPlayerService`.
@MainActor
final class WatchDownloadService {
  static let shared = WatchDownloadService()

  private let fileManager = FileManager.default
  private let cacheDirectory: URL
  private let metadataKey = "amperfy_watch_downloads_meta"

  var cacheLimit: Int64 = 1_073_741_824 // 1 GB default

  private init() {
    let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    self.cacheDirectory = caches.appendingPathComponent("AmperfyDownloads")
    try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
  }

  private func fileURL(for playableId: String) -> URL {
    cacheDirectory.appendingPathComponent("\(playableId).mp3")
  }

  func isDownloaded(playableId: String) async -> Bool {
    fileManager.fileExists(atPath: fileURL(for: playableId).path)
  }

  func toggleDownload(playable: WatchPlayableInfo) async -> Bool {
    if await isDownloaded(playableId: playable.id) {
      await removeDownload(playableId: playable.id)
      return false
    } else {
      await downloadSong(playable)
      return true
    }
  }

  func downloadSong(_ song: WatchPlayableInfo) async {
    guard let url = try? SubsonicClient.shared.downloadUrl(forPlayableId: song.id) else { return }
    let destination = fileURL(for: song.id)
    do {
      var request = URLRequest(url: url)
      for (key, value) in SubsonicClient.shared.httpHeaders {
        request.setValue(value, forHTTPHeaderField: key)
      }
      let (data, response) = try await URLSession.shared.data(for: request)
      if let http = response as? HTTPURLResponse,
         !(200 ..< 300).contains(http.statusCode) { return }
      try data.write(to: destination)
      var meta = loadMetadata()
      meta[song.id] = song
      saveMetadata(meta)
    } catch {
      print("Download failed: \(error)")
    }
  }

  func removeDownload(playableId: String) async {
    try? fileManager.removeItem(at: fileURL(for: playableId))
    var meta = loadMetadata()
    meta.removeValue(forKey: playableId)
    saveMetadata(meta)
  }

  func clearAllDownloads() async {
    let files = (try? fileManager.contentsOfDirectory(
      at: cacheDirectory,
      includingPropertiesForKeys: nil
    )) ?? []
    for file in files { try? fileManager.removeItem(at: file) }
    saveMetadata([:])
  }

  func getDownloadedSongs() async -> [WatchPlayableInfo] {
    Array(loadMetadata().values.sorted { $0.title < $1.title })
  }

  func getTotalDownloadSize() async -> Int64 {
    let files = (try? fileManager.contentsOfDirectory(
      at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]
    )) ?? []
    var total: Int64 = 0
    for file in files {
      let values = try? file.resourceValues(forKeys: [.fileSizeKey])
      if let size = values?.fileSize { total += Int64(size) }
    }
    return total
  }

  func getCachedFileURL(for playableId: String) async -> URL? {
    let url = fileURL(for: playableId)
    return fileManager.fileExists(atPath: url.path) ? url : nil
  }

  // MARK: - Metadata persistence (song info for downloaded files)

  private func metadataURL() -> URL {
    cacheDirectory.appendingPathComponent("metadata.json")
  }

  private func loadMetadata() -> [String: WatchPlayableInfo] {
    guard let data = try? Data(contentsOf: metadataURL()),
          let meta = try? JSONDecoder().decode([String: WatchPlayableInfo].self, from: data)
    else { return [:] }
    return meta
  }

  private func saveMetadata(_ meta: [String: WatchPlayableInfo]) {
    guard let data = try? JSONEncoder().encode(meta) else { return }
    try? data.write(to: metadataURL())
  }
}
