//
//  SubsonicClient.swift
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

import CryptoKit
import Foundation

// MARK: - WatchApiError

/// Errors surfaced by the Subsonic client.
enum WatchApiError: LocalizedError {
  case notAuthenticated
  case invalidUrl
  case badResponse(String)
  case server(String)
  /// A Subsonic `error` object from the response envelope (numeric code + message).
  case subsonicError(code: Int, message: String)
  case transport(Error)

  var errorDescription: String? {
    switch self {
    case .notAuthenticated: return "Not logged in."
    case .invalidUrl: return "The server URL is invalid."
    case let .badResponse(detail): return "Unexpected response from server: \(detail)"
    case let .server(detail): return "Server error: \(detail)"
    case let .subsonicError(code, message): return "Server error \(code): \(message)"
    case let .transport(error): return "Network error: \(error.localizedDescription)"
    }
  }
}

// MARK: - SubsonicClient

/// A self-contained Subsonic-API client for watchOS. Replicates the auth scheme used
/// by AmperfyKit: requests go to `<server>/rest/<action>.view` (Ampache uses its
/// Subsonic-compatible endpoint `<server>/rest/server.php`) with salted token auth
/// (`t = md5(password + salt)`, `s = salt`), or with legacy plain-password auth (`p`)
/// for servers that reject tokens — mirroring AmperfyKit's auth auto-detection.
/// Responses are requested as JSON (`f=json`).
final class SubsonicClient {
  static let shared = SubsonicClient()

  /// Client API version advertised to the server. 1.16.1 is widely supported and
  /// guarantees token auth is available.
  private let clientApiVersion = "1.16.1"
  /// Version advertised with legacy password auth; mirrors AmperfyKit's
  /// `defaultClientApiVersionPreToken`.
  private let legacyClientApiVersion = "1.11.0"
  private let clientName = "AmperfyWatch"

  private let session: URLSession
  private let jsonDecoder: JSONDecoder

  private(set) var credentials: WatchCredentials?

  private init() {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 20
    config.waitsForConnectivity = false
    self.session = URLSession(configuration: config)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    self.jsonDecoder = decoder
  }

  func setCredentials(_ credentials: WatchCredentials?) {
    self.credentials = credentials
  }

  var isAuthenticated: Bool { credentials != nil }

  // MARK: - Auth & URL building

  private func md5Hex(_ string: String) -> String {
    let data = Data(string.utf8)
    return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func randomSalt(length: Int = 16) -> String {
    let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return String((0 ..< length).compactMap { _ in chars.randomElement() })
  }

  private func normalizedServerUrl(_ raw: String) -> URL? {
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }
    if !trimmed.contains("://") {
      trimmed = "https://" + trimmed
    }
    // Keep any path in the server URL: the API must be requested under the same
    // base path the server is hosted at (reverse proxies, tunnel path routing,
    // Ampache). AmperfyKit on iOS preserves it too via URL.appendPathComponent.
    guard var comps = URLComponents(string: trimmed) else { return nil }
    comps.query = nil
    comps.fragment = nil
    while comps.path.hasSuffix("/") {
      comps.path = String(comps.path.dropLast())
    }
    return comps.url
  }

  /// Builds an authenticated URL for a Subsonic action, optionally with an `id` and
  /// extra query items. The auth token + salt are appended so the URL can be handed
  /// directly to AVPlayer / AsyncImage.
  func makeAuthUrl(
    action: String,
    id: String? = nil,
    extra: [URLQueryItem] = []
  ) throws
    -> URL {
    guard let credentials else { throw WatchApiError.notAuthenticated }
    return try makeAuthUrl(action: action, id: id, extra: extra, credentials: credentials)
  }

  /// Builds an authenticated URL using the given credentials rather than the
  /// currently stored ones — needed while probing which auth scheme works.
  private func makeAuthUrl(
    action: String,
    id: String?,
    extra: [URLQueryItem],
    credentials: WatchCredentials
  ) throws
    -> URL {
    guard let base = normalizedServerUrl(credentials.serverUrl),
          var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
    else { throw WatchApiError.invalidUrl }

    let backend = credentials.backendApi
    if backend == .ampache {
      comps.path += "/rest/server.php"
      // Ampache's Subsonic endpoint uses ?action=<action> instead of /<action>.view
      comps.queryItems = [URLQueryItem(name: "action", value: action)]
    } else {
      comps.path += "/rest/\(action).view"
      comps.queryItems = []
    }

    var items = comps.queryItems ?? []
    items.append(URLQueryItem(name: "u", value: credentials.username))
    // Legacy-auth servers predate token auth; AmperfyKit advertises 1.11.0 there.
    items.append(URLQueryItem(
      name: "v",
      value: backend == .subsonic_legacy ? legacyClientApiVersion : clientApiVersion
    ))
    items.append(URLQueryItem(name: "c", value: clientName))
    items.append(URLQueryItem(name: "f", value: "json"))

    if backend == .subsonic_legacy {
      // Legacy auth: plain password, no salt — mirrors AmperfyKit's legacy branch.
      items.append(URLQueryItem(name: "p", value: credentials.password))
    } else {
      let salt = randomSalt()
      let token = md5Hex("\(credentials.password)\(salt)")
      items.append(URLQueryItem(name: "t", value: token))
      items.append(URLQueryItem(name: "s", value: salt))
    }

    if let id { items.append(URLQueryItem(name: "id", value: id)) }
    items.append(contentsOf: extra)
    comps.queryItems = items
    guard let url = comps.url else { throw WatchApiError.invalidUrl }
    return url
  }

  /// HTTP headers to attach to data requests and AVPlayer assets (e.g. Cloudflare Access).
  var httpHeaders: [String: String] { credentials?.httpHeaders ?? [:] }

  // MARK: - Requesting

  /// Converts a non-ok `subsonic-response` envelope into an error, reading the
  /// nested `error` object (`{"code": …, "message": …}`) that Subsonic servers
  /// return instead of a top-level `message`.
  private static func envelopeError(
    _ envelope: [String: Any],
    fallback: String
  ) -> WatchApiError {
    guard let error = envelope["error"] as? [String: Any] else {
      return .server(fallback)
    }
    return .subsonicError(
      code: error["code"] as? Int ?? 0,
      message: error["message"] as? String ?? "unknown error"
    )
  }

  /// Performs a JSON request and decodes a payload key from `subsonic-response`.
  private func request<T: Decodable>(
    action: String,
    id: String? = nil,
    extra: [URLQueryItem] = [],
    payloadKey: String
  ) async throws
    -> T {
    let url = try makeAuthUrl(action: action, id: id, extra: extra)
    var request = URLRequest(url: url)
    for (key, value) in httpHeaders { request.setValue(value, forHTTPHeaderField: key) }

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw WatchApiError.transport(error)
    }
    guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
      throw WatchApiError.badResponse("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
    }

    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let envelope = root["subsonic-response"] as? [String: Any]
    else {
      throw WatchApiError.badResponse("not a subsonic-response document")
    }

    if let status = envelope["status"] as? String, status != "ok" {
      throw Self.envelopeError(envelope, fallback: "status '\(status)'")
    }

    guard let payload = envelope[payloadKey] else {
      throw WatchApiError.badResponse("missing '\(payloadKey)'")
    }

    let payloadData = try JSONSerialization.data(withJSONObject: payload)
    do {
      return try jsonDecoder.decode(T.self, from: payloadData)
    } catch {
      throw WatchApiError
        .badResponse("could not decode '\(payloadKey)': \(error.localizedDescription)")
    }
  }

  // MARK: - Endpoints

  /// Validates credentials against the server (Subsonic `ping`). Mirrors AmperfyKit's
  /// auth auto-detection: if salted-token auth is rejected — wrong credentials
  /// (error 40) or, for LDAP-backed accounts, "token authentication not supported"
  /// (error 41) — retries once with legacy plain-password auth and remembers the
  /// working scheme so all later requests (incl. stream URLs) use it.
  func ping() async throws {
    guard let credentials else { throw WatchApiError.notAuthenticated }
    do {
      try await performPing(credentials: credentials)
    } catch {
      guard case let WatchApiError.subsonicError(code, _) = error,
            code == 40 || code == 41,
            credentials.backendApi == .subsonic || credentials.backendApi == .notDetected
      else { throw error }
      var legacyCredentials = credentials
      legacyCredentials.backendApi = .subsonic_legacy
      try await performPing(credentials: legacyCredentials)
      self.credentials = legacyCredentials
    }
  }

  private func performPing(credentials: WatchCredentials) async throws {
    let url = try makeAuthUrl(action: "ping", id: nil, extra: [], credentials: credentials)
    var request = URLRequest(url: url)
    for (key, value) in credentials.httpHeaders {
      request.setValue(value, forHTTPHeaderField: key)
    }
    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw WatchApiError.transport(error)
    }
    guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
      throw WatchApiError.badResponse("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
    }
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let envelope = root["subsonic-response"] as? [String: Any]
    else { throw WatchApiError.badResponse("not a subsonic-response document") }

    if let status = envelope["status"] as? String, status != "ok" {
      throw Self.envelopeError(envelope, fallback: "status '\(status)'")
    }
  }

  func search(query: String) async throws -> WatchSearchResults {
    let extra = [
      URLQueryItem(name: "query", value: query),
      URLQueryItem(name: "artistCount", value: "20"),
      URLQueryItem(name: "albumCount", value: "20"),
      URLQueryItem(name: "songCount", value: "30"),
    ]
    return try await request(action: "search3", extra: extra, payloadKey: "searchResult3")
  }

  func getArtists() async throws -> [WatchArtist] {
    // Flatten the index groups into a single artist list.
    struct IndexGroup: Decodable { let artist: [WatchArtist]? }
    struct ArtistsContainer: Decodable { let index: [IndexGroup]? }
    let container: ArtistsContainer = try await request(
      action: "getArtists", payloadKey: "artists"
    )
    return container.index?.flatMap { $0.artist ?? [] } ?? []
  }

  func getAlbums(type: String = "newest", size: Int = 50) async throws -> [WatchAlbum] {
    struct AlbumList: Decodable { let album: [WatchAlbum]? }
    let extra = [
      URLQueryItem(name: "type", value: type),
      URLQueryItem(name: "size", value: String(size)),
    ]
    let list: AlbumList = try await request(
      action: "getAlbumList2", extra: extra, payloadKey: "albumList2"
    )
    return list.album ?? []
  }

  func getAlbum(id: String) async throws -> WatchAlbumWithSongs {
    struct AlbumResponse: Decodable {
      let id: String
      let name: String
      let artist: String?
      let artistId: String?
      let songCount: Int?
      let coverArt: String?
      let song: [WatchSongDTO]?
    }
    let album: AlbumResponse = try await request(action: "getAlbum", id: id, payloadKey: "album")
    return WatchAlbumWithSongs(
      album: WatchAlbum(
        id: album.id,
        name: album.name,
        artistName: album.artist,
        artistId: album.artistId,
        songCount: album.songCount,
        artworkId: album.coverArt
      ),
      songs: (album.song ?? []).map { $0.toPlayable() }
    )
  }

  func getPlaylists() async throws -> [WatchPlaylist] {
    struct PlaylistsContainer: Decodable { let playlist: [WatchPlaylistDTO]? }
    let container: PlaylistsContainer = try await request(
      action: "getPlaylists", payloadKey: "playlists"
    )
    return (container.playlist ?? []).map {
      WatchPlaylist(id: $0.id, name: $0.name, songCount: $0.songCount)
    }
  }

  func getPlaylist(id: String) async throws -> [WatchPlayableInfo] {
    struct PlaylistResponse: Decodable { let entry: [WatchSongDTO]? }
    let response: PlaylistResponse = try await request(
      action: "getPlaylist", id: id, payloadKey: "playlist"
    )
    return (response.entry ?? []).map { $0.toPlayable() }
  }

  func getPodcasts() async throws -> [WatchPodcast] {
    struct PodcastDTO: Decodable {
      let id: String
      let name: String?
      let description: String?
      let coverArt: String?
    }
    struct PodcastsContainer: Decodable { let channel: [PodcastDTO]? }
    let container: PodcastsContainer = try await request(
      action: "getPodcasts", extra: [URLQueryItem(name: "includeEpisodes", value: "false")],
      payloadKey: "podcasts"
    )
    return (container.channel ?? []).map {
      WatchPodcast(
        id: $0.id,
        name: $0.name ?? "Podcast",
        description: $0.description,
        artworkId: $0.coverArt
      )
    }
  }

  func getPodcastEpisodes(id: String) async throws -> [WatchPodcastEpisode] {
    struct EpisodeDTO: Decodable {
      let id: String
      let title: String?
      let description: String?
      let duration: Int?
      let publishDate: Int?
      let coverArt: String?
      let streamId: String?
    }
    struct ChannelDTO: Decodable { let episode: [EpisodeDTO]? }
    struct PodcastsContainer: Decodable { let channel: [ChannelDTO]? }
    let container: PodcastsContainer = try await request(
      action: "getPodcasts", id: id,
      extra: [URLQueryItem(name: "includeEpisodes", value: "true")],
      payloadKey: "podcasts"
    )
    let channel = container.channel?.first
    return (channel?.episode ?? []).map { ep in
      WatchPodcastEpisode(
        id: ep.streamId ?? ep.id,
        title: ep.title ?? "Episode",
        description: ep.description,
        duration: TimeInterval(ep.duration ?? 0),
        publishedDate: ep.publishDate.map { Date(timeIntervalSince1970: TimeInterval($0)) },
        artworkId: ep.coverArt
      )
    }
  }

  func getArtistAlbums(artistId: String) async throws -> [WatchAlbum] {
    struct ArtistResponse: Decodable { let album: [WatchAlbumDTO]? }
    let response: ArtistResponse = try await request(
      action: "getArtist", id: artistId, payloadKey: "artist"
    )
    return (response.album ?? []).map { $0.toAlbum() }
  }

  func getArtistSongs(artistId: String) async throws -> [WatchPlayableInfo] {
    // Subsonic has no direct "artist songs" call; collect from the artist's albums.
    let albums = try await getArtistAlbums(artistId: artistId)
    var songs: [WatchPlayableInfo] = []
    for album in albums {
      let detail = try await getAlbum(id: album.id)
      songs.append(contentsOf: detail.songs)
    }
    return songs
  }

  // MARK: - Media URLs

  /// URL for streaming a playable. Auth is in the query string so AVPlayer can use it
  /// directly; custom HTTP headers (Cloudflare Access) are applied via the asset options.
  func streamUrl(forPlayableId id: String) throws -> URL {
    try makeAuthUrl(action: "stream", id: id, extra: [URLQueryItem(name: "format", value: "mp3")])
  }

  func downloadUrl(forPlayableId id: String) throws -> URL {
    try makeAuthUrl(action: "download", id: id)
  }

  func coverArtUrl(forArtworkId id: String) throws -> URL {
    try makeAuthUrl(action: "getCoverArt", id: id)
  }
}

// MARK: - WatchSongDTO

private struct WatchSongDTO: Decodable {
  let id: String
  let title: String?
  let artist: String?
  let album: String?
  let coverArt: String?
  let duration: Int?

  func toPlayable() -> WatchPlayableInfo {
    WatchPlayableInfo(
      id: id,
      title: title ?? "Unknown",
      artistName: artist ?? "Unknown Artist",
      albumName: album ?? "",
      artworkId: coverArt,
      duration: TimeInterval(duration ?? 0)
    )
  }
}

// MARK: - WatchAlbumDTO

private struct WatchAlbumDTO: Decodable {
  let id: String
  let name: String
  let artist: String?
  let artistId: String?
  let songCount: Int?
  let coverArt: String?

  func toAlbum() -> WatchAlbum {
    WatchAlbum(
      id: id, name: name, artistName: artist, artistId: artistId,
      songCount: songCount, artworkId: coverArt
    )
  }
}

// MARK: - WatchPlaylistDTO

private struct WatchPlaylistDTO: Decodable {
  let id: String
  let name: String
  let songCount: Int?
}

// MARK: - WatchAlbumWithSongs

struct WatchAlbumWithSongs {
  let album: WatchAlbum
  let songs: [WatchPlayableInfo]
}
