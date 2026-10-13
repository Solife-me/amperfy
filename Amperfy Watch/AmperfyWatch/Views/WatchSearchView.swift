//
//  WatchSearchView.swift
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

// MARK: - WatchSearchView

struct WatchSearchView: View {
  @EnvironmentObject
  private var navigation: WatchNavigation
  @StateObject
  private var viewModel = WatchSearchViewModel()

  var body: some View {
    List {
      TextField("Artists, albums, songs", text: $viewModel.searchText)
        .textInputAutocapitalization(.never)
        .submitLabel(.search)
        .onSubmit { Task { await viewModel.search() } }

      if viewModel.isLoading {
        ProgressView().frame(maxWidth: .infinity)
      } else if viewModel.searchResults.artists.isEmpty,
                viewModel.searchResults.albums.isEmpty,
                viewModel.searchResults.songs.isEmpty,
                !viewModel.searchText.isEmpty {
        Text("No results").foregroundColor(.secondary)
      }

      if !viewModel.searchResults.artists.isEmpty {
        Section("Artists") {
          ForEach(viewModel.searchResults.artists) { artist in
            NavigationLink(artist.name) { WatchArtistDetailView(artist: artist) }
          }
        }
      }

      if !viewModel.searchResults.albums.isEmpty {
        Section("Albums") {
          ForEach(viewModel.searchResults.albums) { album in
            NavigationLink(album.name) { WatchAlbumDetailView(album: album) }
          }
        }
      }

      if !viewModel.searchResults.songs.isEmpty {
        Section("Songs") {
          ForEach(
            Array(viewModel.searchResults.songs.enumerated()),
            id: \.element.id
          ) { idx, song in
            WatchSongRow(song: song) {
              Task {
                await playAndShowNowPlaying(
                  queue: viewModel.searchResults.songs,
                  startingAt: idx,
                  navigation: navigation
                )
              }
            }
          }
        }
      }
    }
    .navigationTitle("Search")
    .onChange(of: viewModel.searchText) { _ in viewModel.searchTextChanged() }
  }
}

// MARK: - WatchSearchViewModel

@MainActor
final class WatchSearchViewModel: ObservableObject {
  @Published
  var searchText = ""
  @Published
  var isLoading = false
  @Published
  var searchResults = WatchSearchResults()

  private var debounceTask: Task<Void, Never>?

  /// Debounced search-as-you-type, mirroring the iOS app: wait for a pause in
  /// typing before hitting the server, so each keystroke doesn't fire a request.
  func searchTextChanged() {
    debounceTask?.cancel()
    let query = searchText.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else {
      searchResults = WatchSearchResults()
      return
    }
    debounceTask = Task {
      try? await Task.sleep(nanoseconds: 500_000_000)
      guard !Task.isCancelled else { return }
      await run(query: query)
    }
  }

  /// Immediate search from the keyboard's search button.
  func search() async {
    debounceTask?.cancel()
    let query = searchText.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return }
    await run(query: query)
  }

  private func run(query: String) async {
    isLoading = true
    defer { isLoading = false }
    searchResults = await WatchApi.shared.search(query: query)
  }
}
