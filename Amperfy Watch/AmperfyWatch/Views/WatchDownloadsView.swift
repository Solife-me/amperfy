//
//  WatchDownloadsView.swift
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

// MARK: - WatchDownloadsView

struct WatchDownloadsView: View {
  @EnvironmentObject
  private var navigation: WatchNavigation
  @StateObject
  private var viewModel = WatchDownloadsViewModel()

  var body: some View {
    List {
      Section {
        VStack(spacing: 4) {
          HStack {
            Text(WatchFormatters.bytes(viewModel.storageUsed))
            Spacer()
            Text("of \(WatchFormatters.bytes(viewModel.storageLimit))")
          }
          .font(.caption2)
          .foregroundColor(.secondary)
          ProgressView(
            value: Double(viewModel.storageUsed),
            total: Double(max(viewModel.storageLimit, 1))
          )
        }
      }

      if viewModel.downloadedSongs.isEmpty {
        Text("No downloaded songs").foregroundColor(.secondary)
      } else {
        ForEach(Array(viewModel.downloadedSongs.enumerated()), id: \.element.id) { idx, song in
          WatchSongRow(song: song) {
            Task {
              await playAndShowNowPlaying(
                queue: viewModel.downloadedSongs, startingAt: idx, navigation: navigation
              )
            }
          }
          .swipeActions {
            Button(role: .destructive) {
              Task { await viewModel.removeDownload(song) }
            } label: {
              Image(systemName: "trash")
            }
          }
        }
      }

      if !viewModel.downloadedSongs.isEmpty {
        Section {
          Button("Clear All Downloads", role: .destructive) {
            Task { await viewModel.clearAllDownloads() }
          }
        }
      }
    }
    .navigationTitle("Downloads")
    .refreshable { await viewModel.loadDownloads() }
    .task { await viewModel.loadDownloads() }
  }
}

// MARK: - WatchDownloadsViewModel

@MainActor
final class WatchDownloadsViewModel: ObservableObject {
  @Published
  var downloadedSongs: [WatchPlayableInfo] = []
  @Published
  var storageUsed: Int64 = 0
  @Published
  var storageLimit: Int64 = 1_073_741_824

  func loadDownloads() async {
    downloadedSongs = await WatchDownloadService.shared.getDownloadedSongs()
    storageUsed = await WatchDownloadService.shared.getTotalDownloadSize()
    storageLimit = WatchDownloadService.shared.cacheLimit
  }

  func removeDownload(_ song: WatchPlayableInfo) async {
    await WatchDownloadService.shared.removeDownload(playableId: song.id)
    await loadDownloads()
  }

  func clearAllDownloads() async {
    await WatchDownloadService.shared.clearAllDownloads()
    await loadDownloads()
  }
}
