//
//  WatchLoginView.swift
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

// MARK: - WatchLoginView

/// Manual on-watch login. The primary provisioning path is the phone pushing
/// credentials over WatchConnectivity; this screen is a fallback for when the
/// companion app isn't available or the user wants to enter credentials directly.
struct WatchLoginView: View {
  @StateObject
  private var viewModel = WatchLoginViewModel()
  @EnvironmentObject
  private var appState: AppState

  var body: some View {
    NavigationStack {
      Form {
        if let hint = appState.provisioningHint {
          Section { Text(hint).font(.caption2).foregroundColor(.orange) }
        }

        Section("Server") {
          TextField("Server URL", text: $viewModel.serverUrl)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
          TextField("Username", text: $viewModel.username)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
          SecureField("Password", text: $viewModel.password)
        }

        Section("API Type") {
          Picker("Type", selection: $viewModel.apiType) {
            Text("Auto-Detect").tag(WatchBackendApi.subsonic)
            Text("Subsonic").tag(WatchBackendApi.subsonic)
            Text("Ampache").tag(WatchBackendApi.ampache)
          }
        }

        Section {
          if appState.isAuthenticating || viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity)
          } else {
            Button("Login") { Task { await viewModel.login(appState: appState) } }
              .disabled(!viewModel.isValid)
          }
        }
      }
      .navigationTitle("Amperfy")
    }
    .alert("Login Failed", isPresented: $viewModel.showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(viewModel.errorMessage)
    }
  }
}

// MARK: - WatchLoginViewModel

@MainActor
final class WatchLoginViewModel: ObservableObject {
  @Published
  var serverUrl = ""
  @Published
  var username = ""
  @Published
  var password = ""
  @Published
  var apiType: WatchBackendApi = .subsonic
  @Published
  var isLoading = false
  @Published
  var showError = false
  @Published
  var errorMessage = ""

  var isValid: Bool {
    !serverUrl.trimmingCharacters(in: .whitespaces).isEmpty &&
      !username.trimmingCharacters(in: .whitespaces).isEmpty &&
      !password.trimmingCharacters(in: .whitespaces).isEmpty
  }

  func login(appState: AppState) async {
    isLoading = true
    defer { isLoading = false }

    let credentials = WatchCredentials(
      serverUrl: serverUrl, username: username, password: password, backendApi: apiType
    )
    do {
      let effective = try await WatchApi.shared.login(credentials: credentials)
      WatchCredentialStore.shared.save(effective)
      appState.setAuthenticated(true)
    } catch {
      errorMessage = error.localizedDescription
      showError = true
    }
  }
}
