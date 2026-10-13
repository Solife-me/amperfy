//
//  WatchModels.swift
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

// MARK: - WatchRepeatMode

/// Repeat behavior of the watch player, mirroring the iOS player's off/all/single cycle.
enum WatchRepeatMode: Int, Codable, Sendable {
  case off = 0
  case all = 1
  case one = 2

  mutating func cycle() {
    self = WatchRepeatMode(rawValue: (rawValue + 1) % 3) ?? .off
  }

  var displayName: String {
    switch self {
    case .off: return "Repeat Off"
    case .all: return "Repeat All"
    case .one: return "Repeat One"
    }
  }

  var systemImage: String {
    self == .one ? "repeat.1" : "repeat"
  }
}

// MARK: - WatchBackendApi

/// The backend API the provisioned account speaks. The watch always talks to the
/// server through the Subsonic API; for Ampache servers it uses Ampache's
/// Subsonic-compatible endpoint (`/rest/server.php`).
enum WatchBackendApi: Int, Codable, Sendable {
  case notDetected = 0
  case ampache = 1
  case subsonic = 2
  /// Subsonic API with legacy plain-password auth, for servers that reject salted
  /// tokens (e.g. LDAP-backed accounts). Matches AmperfyKit's `subsonic_legacy`.
  case subsonic_legacy = 3

  var displayName: String {
    switch self {
    case .notDetected: return "Auto-Detect"
    case .ampache: return "Ampache"
    case .subsonic: return "Subsonic"
    case .subsonic_legacy: return "Subsonic (legacy login)"
    }
  }
}

// MARK: - WatchCredentials

/// Credentials provisioned from the phone (WatchConnectivity) or entered manually
/// on the watch. Stored in the watch Keychain.
struct WatchCredentials: Codable, Sendable, Equatable {
  var serverUrl: String
  var username: String
  var password: String
  var backendApi: WatchBackendApi
  /// Custom HTTP headers (e.g. Cloudflare Access service token) forwarded to the server.
  var httpHeaders: [String: String]

  init(
    serverUrl: String,
    username: String,
    password: String,
    backendApi: WatchBackendApi = .subsonic,
    httpHeaders: [String: String] = [:]
  ) {
    self.serverUrl = serverUrl
    self.username = username
    self.password = password
    self.backendApi = backendApi
    self.httpHeaders = httpHeaders
  }
}

// MARK: - WatchPlayableInfo

struct WatchPlayableInfo: Identifiable, Codable, Sendable, Equatable {
  let id: String
  let title: String
  let artistName: String
  let albumName: String
  let artworkId: String?
  let duration: TimeInterval

  init(
    id: String,
    title: String,
    artistName: String,
    albumName: String,
    artworkId: String? = nil,
    duration: TimeInterval = 0
  ) {
    self.id = id
    self.title = title
    self.artistName = artistName
    self.albumName = albumName
    self.artworkId = artworkId
    self.duration = duration
  }
}

// MARK: - WatchArtist

struct WatchArtist: Identifiable, Codable, Sendable, Equatable {
  let id: String
  let name: String
  let albumCount: Int?
  let artworkId: String?
}

// MARK: - WatchAlbum

struct WatchAlbum: Identifiable, Codable, Sendable, Equatable {
  let id: String
  let name: String
  let artistName: String?
  let artistId: String?
  let songCount: Int?
  let artworkId: String?
}

// MARK: - WatchPlaylist

struct WatchPlaylist: Identifiable, Codable, Sendable, Equatable {
  let id: String
  let name: String
  let songCount: Int?
}

// MARK: - WatchPodcast

struct WatchPodcast: Identifiable, Codable, Sendable, Equatable {
  let id: String
  let name: String
  let description: String?
  let artworkId: String?
}

// MARK: - WatchPodcastEpisode

struct WatchPodcastEpisode: Identifiable, Codable, Sendable, Equatable {
  let id: String
  let title: String
  let description: String?
  let duration: TimeInterval
  let publishedDate: Date?
  let artworkId: String?

  var formattedDuration: String {
    WatchFormatters.duration(duration)
  }
}

// MARK: - WatchSearchResults

struct WatchSearchResults: Codable, Sendable, Equatable {
  var artists: [WatchArtist] = []
  var albums: [WatchAlbum] = []
  var songs: [WatchPlayableInfo] = []
}

// MARK: - WatchFormatters

enum WatchFormatters {
  static func duration(_ time: TimeInterval) -> String {
    guard time.isFinite, time > 0 else { return "0:00" }
    let total = Int(time)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }

  static func bytes(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.allowedUnits = [.useMB, .useGB]
    f.countStyle = .file
    return f.string(fromByteCount: bytes)
  }
}
