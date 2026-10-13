//
//  WatchHomeView.swift
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

// MARK: - WatchNavigation

/// Coordinates navigation across the watch app. Mirrors the iOS app's mini player
/// pattern: any screen can present Now Playing (e.g. after starting a song), and
/// SwiftUI keeps `isNowPlayingPresented` in sync when the user pops back.
@MainActor
final class WatchNavigation: ObservableObject {
  @Published
  var isNowPlayingPresented = false

  func showNowPlaying() {
    isNowPlayingPresented = true
  }
}

// MARK: - WatchHomeView

/// Root screen. A menu list of the library categories (like the iOS Library tab),
/// with a mini-player row at the top whenever something is playing.
struct WatchHomeView: View {
  @EnvironmentObject
  private var appState: AppState
  @StateObject
  private var navigation = WatchNavigation()
  @ObservedObject
  private var player = WatchPlayerService.shared
  @State
  private var isConfirmingSignOut = false

  var body: some View {
    NavigationStack {
      List {
        if player.currentSong != nil {
          Section {
            NowPlayingMenuRow { navigation.showNowPlaying() }
          }
        }

        Section {
          WatchMenuRow(
            title: "Search", systemImage: "magnifyingglass", tint: .gray
          ) { WatchSearchView() }
          WatchMenuRow(
            title: "Recently Added", systemImage: "clock.fill", tint: .green
          ) { WatchRecentSongsView() }
          WatchMenuRow(
            title: "Playlists", systemImage: "music.note.list", tint: .pink
          ) { WatchPlaylistListView() }
          WatchMenuRow(
            title: "Artists", systemImage: "music.mic", tint: .purple
          ) { WatchArtistListView() }
          WatchMenuRow(
            title: "Albums", systemImage: "square.stack.fill", tint: .orange
          ) { WatchAlbumListView() }
          WatchMenuRow(
            title: "Podcasts", systemImage: "dot.radiowaves.left.and.right", tint: .indigo
          ) { WatchPodcastListView() }
          WatchMenuRow(
            title: "Downloads", systemImage: "arrow.down.circle.fill", tint: .teal
          ) { WatchDownloadsView() }
        }

        Section {
          Button("Sign Out", role: .destructive) { isConfirmingSignOut = true }
        }
      }
      .navigationTitle("Amperfy")
      .navigationDestination(isPresented: $navigation.isNowPlayingPresented) {
        WatchNowPlayingView()
      }
      .confirmationDialog(
        "Sign out of Amperfy?",
        isPresented: $isConfirmingSignOut,
        titleVisibility: .visible
      ) {
        Button("Sign Out", role: .destructive) { appState.logout() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Downloaded songs stay on this watch.")
      }
    }
    .environmentObject(navigation)
  }
}

// MARK: - WatchMenuRow

/// A navigation row with a tinted icon tile, styled after the iOS Library list.
struct WatchMenuRow<Destination: View>: View {
  let title: String
  let systemImage: String
  let tint: Color
  @ViewBuilder
  let destination: () -> Destination

  var body: some View {
    NavigationLink(destination: destination) {
      Label {
        Text(title)
      } icon: {
        Image(systemName: systemImage)
          .font(.callout)
          .foregroundStyle(tint)
          .frame(width: 26, height: 26)
          .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
      }
    }
  }
}

// MARK: - NowPlayingMenuRow

/// Mini-player row shown at the top of Home while music is playing — the watch
/// analog of the iOS app's mini player bar.
struct NowPlayingMenuRow: View {
  @ObservedObject
  private var player = WatchPlayerService.shared
  let onTap: () -> ()

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 8) {
        WatchArtworkView(artworkId: player.currentSong?.artworkId, size: 30)
        VStack(alignment: .leading, spacing: 1) {
          Text(player.currentSong?.title ?? "")
            .font(.subheadline).lineLimit(1)
          Text(player.currentSong?.artistName ?? "")
            .font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }
        Spacer(minLength: 4)
        Image(systemName: "waveform")
          .font(.callout)
          .foregroundStyle(Color.accentColor)
          .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
      }
    }
    .buttonStyle(.plain)
  }
}
