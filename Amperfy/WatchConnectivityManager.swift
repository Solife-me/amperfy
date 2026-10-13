//
//  WatchConnectivityManager.swift
//  Amperfy
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

import AmperfyKit
import Foundation
import WatchConnectivity

// MARK: - WatchConnectivityManager

/// Provisions the Amperfy Watch app with the user's server credentials over
/// WatchConnectivity. The watch stores them locally and uses them to talk to the
/// Subsonic/Ampache server directly (streaming + downloads) when untethered.
final class WatchConnectivityManager: NSObject, @unchecked Sendable {
  static let shared = WatchConnectivityManager()

  private var session: WCSession?

  private override init() {
    super.init()
  }

  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
    self.session = session
  }

  /// Push the current account credentials to the watch. Delivered via
  /// `updateApplicationContext` (latest state, delivered on next watch wake) and
  /// `transferUserInfo` (queued, reliable).
  func pushCredentials(_ credentials: LoginCredentials) {
    guard let session, session.activationState == .activated else { return }
    guard let data = encodeCredentials(credentials) else { return }
    let payload: [String: Any] = ["credentials": data]
    try? session.updateApplicationContext(payload)
    session.transferUserInfo(payload)
  }

  /// Encode credentials to the JSON shape the watch's `WatchCredentials` expects.
  private func encodeCredentials(_ c: LoginCredentials) -> Data? {
    // Pass the detected backend through verbatim, including subsonic_legacy: the
    // phone only lands on that type after salted-token auth was rejected (e.g.
    // LDAP-backed accounts), and the watch must know to use legacy password auth.
    let backendInt = c.backendApi.rawValue
    let serverUrl = c.activeBackendServerUrl.isEmpty ? c.serverUrl : c.activeBackendServerUrl
    let dict: [String: Any] = [
      "serverUrl": serverUrl,
      "username": c.username,
      "password": c.password,
      "backendApi": backendInt,
      "httpHeaders": c.httpHeaders,
    ]
    return try? JSONSerialization.data(withJSONObject: dict)
  }
}

// MARK: WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {}

  #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
      // Re-activate for the next paired watch.
      session.activate()
    }
  #endif
}
