//
//  WatchApi.swift
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

/// Facade the SwiftUI views talk to. Wraps `SubsonicClient` and converts throwing
/// calls into the non-throwing array results the view models expect.
@MainActor
final class WatchApi {
  static let shared = WatchApi()

  private let client = SubsonicClient.shared
  private init() {}

  var isAuthenticated: Bool { client.isAuthenticated }
  var credentials: WatchCredentials? { client.credentials }

  func setCredentials(_ credentials: WatchCredentials?) {
    client.setCredentials(credentials)
  }

  /// Validates credentials against the server. Throws on failure. Returns the
  /// credentials that actually authenticated — the client may have switched to
  /// legacy password auth if the server rejected salted tokens — so callers can
  /// persist them.
  @discardableResult
  func login(credentials: WatchCredentials) async throws -> WatchCredentials {
    client.setCredentials(credentials)
    try await client.ping()
    return client.credentials ?? credentials
  }

  func logout() {
    client.setCredentials(nil)
  }

  // MARK: - Library

  func getRecentSongs(limit: Int) async -> [WatchPlayableInfo] {
    // Subsonic has no "recently played" without scrobbling; surface the newest
    // additions by pulling the most recent albums and their first track.
    let albums = (try? await client.getAlbums(type: "newest", size: max(limit, 20))) ?? []
    var songs: [WatchPlayableInfo] = []
    for album in albums.prefix(limit) {
      if let detail = try? await client.getAlbum(id: album.id),
         let first = detail.songs.first {
        songs.append(first)
      }
    }
    return Array(songs.prefix(limit))
  }

  func getArtists(limit: Int) async -> [WatchArtist] {
    let artists = (try? await client.getArtists()) ?? []
    return Array(artists.prefix(limit))
  }

  func getAlbums(limit: Int, type: String = "newest") async -> [WatchAlbum] {
    (try? await client.getAlbums(type: type, size: limit)) ?? []
  }

  func getPlaylists() async -> [WatchPlaylist] {
    (try? await client.getPlaylists()) ?? []
  }

  func getPodcasts() async -> [WatchPodcast] {
    (try? await client.getPodcasts()) ?? []
  }

  func getArtistAlbums(artistId: String) async -> [WatchAlbum] {
    (try? await client.getArtistAlbums(artistId: artistId)) ?? []
  }

  func getArtistSongs(artistId: String) async -> [WatchPlayableInfo] {
    (try? await client.getArtistSongs(artistId: artistId)) ?? []
  }

  func getAlbumSongs(albumId: String) async -> [WatchPlayableInfo] {
    ((try? await client.getAlbum(id: albumId))?.songs) ?? []
  }

  func getPlaylistSongs(playlistId: String) async -> [WatchPlayableInfo] {
    (try? await client.getPlaylist(id: playlistId)) ?? []
  }

  func getPodcastEpisodes(podcastId: String) async -> [WatchPodcastEpisode] {
    (try? await client.getPodcastEpisodes(id: podcastId)) ?? []
  }

  func search(query: String) async -> WatchSearchResults {
    (try? await client.search(query: query)) ?? WatchSearchResults()
  }
}
