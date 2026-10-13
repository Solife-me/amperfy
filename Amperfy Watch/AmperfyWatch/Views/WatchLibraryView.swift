//
//  WatchLibraryView.swift
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

// MARK: - Playback helper

/// Starts playback and presents Now Playing. On the watch there is no persistent
/// mini player on pushed screens, so starting music navigates straight to the
/// player (like Apple Music does).
@MainActor
func playAndShowNowPlaying(
  queue: [WatchPlayableInfo],
  startingAt index: Int,
  navigation: WatchNavigation
) async {
  await WatchPlayerService.shared.play(queue: queue, startingAt: index)
  navigation.showNowPlaying()
}

// MARK: - WatchRecentSongsView

struct WatchRecentSongsView: View {
  @EnvironmentObject
  private var navigation: WatchNavigation
  @StateObject
  private var viewModel = WatchRecentSongsViewModel()

  var body: some View {
    WatchSongsList(
      songs: viewModel.recentSongs,
      isLoading: viewModel.isLoading,
      emptyText: "Nothing here yet"
    ) { idx in
      Task {
        await playAndShowNowPlaying(
          queue: viewModel.recentSongs, startingAt: idx, navigation: navigation
        )
      }
    }
    .navigationTitle("Recently Added")
    .refreshable { await viewModel.refresh() }
    .task { await viewModel.loadIfNeeded() }
  }
}

@MainActor
final class WatchRecentSongsViewModel: ObservableObject {
  @Published
  private(set) var recentSongs: [WatchPlayableInfo] = []
  @Published
  private(set) var isLoading = false

  func loadIfNeeded() async {
    guard recentSongs.isEmpty else { return }
    await load()
  }

  func refresh() async { await load() }

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    recentSongs = await WatchApi.shared.getRecentSongs(limit: 30)
  }
}

// MARK: - WatchArtistListView

struct WatchArtistListView: View {
  @StateObject
  private var viewModel = WatchArtistListViewModel()

  var body: some View {
    List {
      if viewModel.artists.isEmpty {
        if viewModel.isLoading {
          ProgressView().frame(maxWidth: .infinity)
        } else {
          Text("No artists").foregroundColor(.secondary)
        }
      } else {
        ForEach(viewModel.artists) { artist in
          NavigationLink {
            WatchArtistDetailView(artist: artist)
          } label: {
            Text(artist.name).lineLimit(1)
          }
        }
      }
    }
    .navigationTitle("Artists")
    .refreshable { await viewModel.refresh() }
    .task { await viewModel.loadIfNeeded() }
  }
}

@MainActor
final class WatchArtistListViewModel: ObservableObject {
  @Published
  private(set) var artists: [WatchArtist] = []
  @Published
  private(set) var isLoading = false

  func loadIfNeeded() async {
    guard artists.isEmpty else { return }
    await load()
  }

  func refresh() async { await load() }

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    artists = await WatchApi.shared.getArtists(limit: 1_000)
  }
}

// MARK: - WatchAlbumListView

struct WatchAlbumListView: View {
  @StateObject
  private var viewModel = WatchAlbumListViewModel()

  var body: some View {
    List {
      if viewModel.albums.isEmpty {
        if viewModel.isLoading {
          ProgressView().frame(maxWidth: .infinity)
        } else {
          Text("No albums").foregroundColor(.secondary)
        }
      } else {
        ForEach(viewModel.albums) { album in
          NavigationLink {
            WatchAlbumDetailView(album: album)
          } label: {
            HStack(spacing: 8) {
              WatchArtworkView(artworkId: album.artworkId, size: 30)
              VStack(alignment: .leading, spacing: 1) {
                Text(album.name).font(.subheadline).lineLimit(1)
                if let artistName = album.artistName {
                  Text(artistName).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
              }
            }
          }
        }
      }
    }
    .navigationTitle("Albums")
    .refreshable { await viewModel.refresh() }
    .task { await viewModel.loadIfNeeded() }
  }
}

@MainActor
final class WatchAlbumListViewModel: ObservableObject {
  @Published
  private(set) var albums: [WatchAlbum] = []
  @Published
  private(set) var isLoading = false

  func loadIfNeeded() async {
    guard albums.isEmpty else { return }
    await load()
  }

  func refresh() async { await load() }

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    albums = await WatchApi.shared.getAlbums(limit: 500, type: "alphabeticalByName")
  }
}

// MARK: - WatchPlaylistListView

struct WatchPlaylistListView: View {
  @StateObject
  private var viewModel = WatchPlaylistListViewModel()

  var body: some View {
    List {
      if viewModel.playlists.isEmpty {
        if viewModel.isLoading {
          ProgressView().frame(maxWidth: .infinity)
        } else {
          Text("No playlists").foregroundColor(.secondary)
        }
      } else {
        ForEach(viewModel.playlists) { playlist in
          NavigationLink {
            WatchPlaylistDetailView(playlist: playlist)
          } label: {
            VStack(alignment: .leading, spacing: 1) {
              Text(playlist.name).font(.subheadline).lineLimit(1)
              if let songCount = playlist.songCount {
                Text("\(songCount) songs").font(.caption2).foregroundColor(.secondary)
              }
            }
          }
        }
      }
    }
    .navigationTitle("Playlists")
    .refreshable { await viewModel.refresh() }
    .task { await viewModel.loadIfNeeded() }
  }
}

@MainActor
final class WatchPlaylistListViewModel: ObservableObject {
  @Published
  private(set) var playlists: [WatchPlaylist] = []
  @Published
  private(set) var isLoading = false

  func loadIfNeeded() async {
    guard playlists.isEmpty else { return }
    await load()
  }

  func refresh() async { await load() }

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    playlists = await WatchApi.shared.getPlaylists()
  }
}

// MARK: - WatchPodcastListView

struct WatchPodcastListView: View {
  @StateObject
  private var viewModel = WatchPodcastListViewModel()

  var body: some View {
    List {
      if viewModel.podcasts.isEmpty {
        if viewModel.isLoading {
          ProgressView().frame(maxWidth: .infinity)
        } else {
          Text("No podcasts").foregroundColor(.secondary)
        }
      } else {
        ForEach(viewModel.podcasts) { podcast in
          NavigationLink {
            WatchPodcastDetailView(podcast: podcast)
          } label: {
            HStack(spacing: 8) {
              WatchArtworkView(artworkId: podcast.artworkId, size: 30)
              Text(podcast.name).font(.subheadline).lineLimit(1)
            }
          }
        }
      }
    }
    .navigationTitle("Podcasts")
    .refreshable { await viewModel.refresh() }
    .task { await viewModel.loadIfNeeded() }
  }
}

@MainActor
final class WatchPodcastListViewModel: ObservableObject {
  @Published
  private(set) var podcasts: [WatchPodcast] = []
  @Published
  private(set) var isLoading = false

  func loadIfNeeded() async {
    guard podcasts.isEmpty else { return }
    await load()
  }

  func refresh() async { await load() }

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    podcasts = await WatchApi.shared.getPodcasts()
  }
}

// MARK: - WatchSongRow

struct WatchSongRow: View {
  let song: WatchPlayableInfo
  let onTap: () -> ()

  var body: some View {
    Button(action: onTap) {
      HStack {
        WatchArtworkView(artworkId: song.artworkId, size: 36)
        VStack(alignment: .leading, spacing: 2) {
          Text(song.title).font(.subheadline).lineLimit(1)
          Text(song.artistName).font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }
      }
    }
    .buttonStyle(.plain)
  }
}

// MARK: - WatchSongsList

/// Shared song-list body for screens that are just a list of playables.
struct WatchSongsList: View {
  let songs: [WatchPlayableInfo]
  let isLoading: Bool
  let emptyText: String
  let onTapSong: (Int) -> ()

  var body: some View {
    List {
      if songs.isEmpty {
        if isLoading {
          ProgressView().frame(maxWidth: .infinity)
        } else {
          Text(emptyText).foregroundColor(.secondary)
        }
      } else {
        ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
          WatchSongRow(song: song) { onTapSong(idx) }
        }
      }
    }
  }
}

// MARK: - WatchArtworkView

/// Loads cover art from the server via AsyncImage. Auth is in the query string so a
/// plain GET works; custom HTTP headers (Cloudflare Access) are not applied to image
/// loads, which is acceptable for artwork.
struct WatchArtworkView: View {
  let artworkId: String?
  let size: CGFloat

  var body: some View {
    Group {
      if let artworkId, let url = try? SubsonicClient.shared.coverArtUrl(forArtworkId: artworkId) {
        AsyncImage(url: url) { phase in
          switch phase {
          case let .success(image):
            image.resizable().aspectRatio(contentMode: .fill)
          default:
            placeholder
          }
        }
      } else {
        placeholder
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private var placeholder: some View {
    RoundedRectangle(cornerRadius: 6)
      .fill(Color.gray.opacity(0.25))
      .overlay(Image(systemName: "music.note").font(.caption))
  }
}

// MARK: - WatchArtistDetailView

struct WatchArtistDetailView: View {
  let artist: WatchArtist
  @EnvironmentObject
  private var navigation: WatchNavigation
  @StateObject
  private var viewModel = WatchArtistDetailViewModel()

  var body: some View {
    List {
      if !viewModel.albums.isEmpty {
        Section("Albums") {
          ForEach(viewModel.albums) { album in
            NavigationLink(album.name) { WatchAlbumDetailView(album: album) }
          }
        }
      }
      if !viewModel.songs.isEmpty {
        Section("Songs") {
          ForEach(Array(viewModel.songs.enumerated()), id: \.element.id) { idx, song in
            WatchSongRow(song: song) {
              Task {
                await playAndShowNowPlaying(
                  queue: viewModel.songs, startingAt: idx, navigation: navigation
                )
              }
            }
          }
        }
      }
    }
    .navigationTitle(artist.name)
    .task { await viewModel.loadArtist(artistId: artist.id) }
  }
}

@MainActor
final class WatchArtistDetailViewModel: ObservableObject {
  @Published
  var albums: [WatchAlbum] = []
  @Published
  var songs: [WatchPlayableInfo] = []

  func loadArtist(artistId: String) async {
    async let albums = WatchApi.shared.getArtistAlbums(artistId: artistId)
    async let songs = WatchApi.shared.getArtistSongs(artistId: artistId)
    self.albums = await albums
    self.songs = await songs
  }
}

// MARK: - WatchAlbumDetailView

struct WatchAlbumDetailView: View {
  let album: WatchAlbum
  @EnvironmentObject
  private var navigation: WatchNavigation
  @StateObject
  private var viewModel = WatchAlbumDetailViewModel()

  var body: some View {
    WatchSongsList(
      songs: viewModel.songs,
      isLoading: viewModel.isLoading,
      emptyText: "No songs"
    ) { idx in
      Task {
        await playAndShowNowPlaying(
          queue: viewModel.songs, startingAt: idx, navigation: navigation
        )
      }
    }
    .navigationTitle(album.name)
    .task { await viewModel.loadAlbum(albumId: album.id) }
  }
}

@MainActor
final class WatchAlbumDetailViewModel: ObservableObject {
  @Published
  private(set) var songs: [WatchPlayableInfo] = []
  @Published
  private(set) var isLoading = false

  func loadAlbum(albumId: String) async {
    isLoading = true
    defer { isLoading = false }
    songs = await WatchApi.shared.getAlbumSongs(albumId: albumId)
  }
}

// MARK: - WatchPlaylistDetailView

struct WatchPlaylistDetailView: View {
  let playlist: WatchPlaylist
  @EnvironmentObject
  private var navigation: WatchNavigation
  @StateObject
  private var viewModel = WatchPlaylistDetailViewModel()

  var body: some View {
    WatchSongsList(
      songs: viewModel.songs,
      isLoading: viewModel.isLoading,
      emptyText: "No songs"
    ) { idx in
      Task {
        await playAndShowNowPlaying(
          queue: viewModel.songs, startingAt: idx, navigation: navigation
        )
      }
    }
    .navigationTitle(playlist.name)
    .task { await viewModel.loadPlaylist(playlistId: playlist.id) }
  }
}

@MainActor
final class WatchPlaylistDetailViewModel: ObservableObject {
  @Published
  private(set) var songs: [WatchPlayableInfo] = []
  @Published
  private(set) var isLoading = false

  func loadPlaylist(playlistId: String) async {
    isLoading = true
    defer { isLoading = false }
    songs = await WatchApi.shared.getPlaylistSongs(playlistId: playlistId)
  }
}

// MARK: - WatchPodcastDetailView

struct WatchPodcastDetailView: View {
  let podcast: WatchPodcast
  @EnvironmentObject
  private var navigation: WatchNavigation
  @StateObject
  private var viewModel = WatchPodcastDetailViewModel()

  var body: some View {
    List {
      if viewModel.episodes.isEmpty {
        if viewModel.isLoading {
          ProgressView().frame(maxWidth: .infinity)
        } else {
          Text("No episodes").foregroundColor(.secondary)
        }
      } else {
        ForEach(viewModel.episodes) { episode in
          Button {
            Task {
              await WatchPlayerService.shared.playEpisode(episode)
              navigation.showNowPlaying()
            }
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(episode.title).font(.subheadline).lineLimit(2)
              Text(episode.formattedDuration).font(.caption2).foregroundColor(.secondary)
            }
          }
          .buttonStyle(.plain)
        }
      }
    }
    .navigationTitle(podcast.name)
    .task { await viewModel.loadPodcast(podcastId: podcast.id) }
  }
}

@MainActor
final class WatchPodcastDetailViewModel: ObservableObject {
  @Published
  private(set) var episodes: [WatchPodcastEpisode] = []
  @Published
  private(set) var isLoading = false

  func loadPodcast(podcastId: String) async {
    isLoading = true
    defer { isLoading = false }
    episodes = await WatchApi.shared.getPodcastEpisodes(podcastId: podcastId)
  }
}
