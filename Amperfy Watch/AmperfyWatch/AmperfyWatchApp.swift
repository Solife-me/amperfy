//
//  AmperfyWatchApp.swift
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
import SwiftUI
import WatchConnectivity

// MARK: - AmperfyWatchApp

@main
struct AmperfyWatchApp: App {
  @StateObject
  private var appState = AppState()

  var body: some Scene {
    WindowGroup {
      if appState.isAuthenticated {
        WatchHomeView()
          .environmentObject(appState)
      } else {
        WatchLoginView()
          .environmentObject(appState)
      }
    }
  }
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {
  @Published
  var isAuthenticated = false
  @Published
  var isAuthenticating = false
  @Published
  var provisioningHint: String?

  private var cancellables = Set<AnyCancellable>()

  init() {
    // Start listening for credentials pushed from the phone.
    let receiver = WatchConnectivityReceiver.shared
    receiver.activate()
    receiver.credentialsReceived
      .receive(on: DispatchQueue.main)
      .sink { [weak self] credentials in
        self?.applyProvisionedCredentials(credentials)
      }
      .store(in: &cancellables)

    // Try silent login with any credentials already stored on the watch.
    if let stored = WatchCredentialStore.shared.load() {
      Task { await self.silentLogin(with: stored) }
    }
  }

  private func applyProvisionedCredentials(_ credentials: WatchCredentials) {
    WatchApi.shared.setCredentials(credentials)
    Task { await silentLogin(with: credentials) }
  }

  func silentLogin(with credentials: WatchCredentials) async {
    isAuthenticating = true
    defer { isAuthenticating = false }
    do {
      let effective = try await WatchApi.shared.login(credentials: credentials)
      // Persist if ping's legacy-auth fallback switched the auth scheme.
      if effective != credentials { WatchCredentialStore.shared.save(effective) }
      isAuthenticated = true
      provisioningHint = nil
    } catch {
      // Keep stored credentials but show the login screen so the user can retry.
      isAuthenticated = false
      provisioningHint =
        "Phone provisioning received but login failed: \(error.localizedDescription)"
    }
  }

  func setAuthenticated(_ value: Bool) {
    isAuthenticated = value
  }

  func logout() {
    WatchCredentialStore.shared.clear()
    WatchApi.shared.logout()
    isAuthenticated = false
  }
}
