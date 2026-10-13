//
//  WatchConnectivityReceiver.swift
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

import Combine
import Foundation
import WatchConnectivity

// MARK: - WatchConnectivityReceiver

/// Receives account credentials provisioned from the companion iOS app over
/// WatchConnectivity. The phone pushes credentials whenever the user logs in or
/// the watch becomes reachable; the watch persists them and re-authenticates.
final class WatchConnectivityReceiver: NSObject, ObservableObject {
  static let shared = WatchConnectivityReceiver()

  /// Posted on the main actor whenever new credentials arrive from the phone.
  let credentialsReceived = PassthroughSubject<WatchCredentials, Never>()

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

  var isCompanionInstalled: Bool {
    WCSession.isSupported() && WCSession.default.isCompanionAppInstalled
  }
}

// MARK: WCSessionDelegate

extension WatchConnectivityReceiver: WCSessionDelegate {
  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    // No-op; we learn companion availability via isCompanionAppInstalled.
  }

  func session(
    _ session: WCSession,
    didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    handlePayload(applicationContext)
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    handlePayload(userInfo)
  }

  private func handlePayload(_ payload: [String: Any]) {
    guard let data = payload["credentials"] as? Data,
          let credentials = try? JSONDecoder().decode(WatchCredentials.self, from: data)
    else { return }
    WatchCredentialStore.shared.save(credentials)
    DispatchQueue.main.async { [weak self] in
      self?.credentialsReceived.send(credentials)
    }
  }
}
