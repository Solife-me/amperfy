# Amperfy Watch

A standalone, independent watchOS app for Amperfy. It talks **directly** to your
Subsonic/Ampache server for streaming and downloads, and plays downloaded songs
offline when the phone is left behind. Account credentials are provisioned from the
companion iOS app over WatchConnectivity; a manual on-watch login is also available
as a fallback.

The watch app is built as a target inside `Amperfy.xcodeproj` (target name
**Amperfy Watch**, product `Amperfy Watch.app`). It does **not** depend on
`AmperfyKit` — AmperfyKit is iOS-only and cannot compile for watchOS — so the
watch app has its own small Subsonic API client.

## Project layout

```
Amperfy.xcodeproj/                  ← single Xcode project, hosts both iOS + watch targets
Amperfy/                            ← iOS app sources
Amperfy Watch/
├── README.md                       ← this file
└── AmperfyWatch/                   ← watch app sources (referenced by Amperfy.xcodeproj)
    ├── AmperfyWatchApp.swift
    ├── AmperfyWatch.entitlements
    ├── Info.plist
    ├── Assets.xcassets/
    ├── Api/         (SubsonicClient, WatchApi)
    ├── Models/      (WatchModels)
    ├── Services/    (WatchConnectivityReceiver, WatchCredentialStore,
    │                 WatchPlayerService, WatchDownloadService)
    └── Views/       (WatchHomeView, WatchLoginView, WatchLibraryView,
                      WatchSearchView, WatchNowPlayingView, WatchDownloadsView)
```

The iOS app target embeds the watch app via the existing `Embed Foundation
Extensions` build phase (`dstSubfolderSpec = 13`, PlugIns folder). Archiving
the iOS app produces a single `.xcarchive` whose payload contains both apps,
so a single upload delivers both to App Store Connect / TestFlight.

## Architecture

- **`Api/SubsonicClient.swift`** — self-contained Subsonic client. Replicates
  AmperfyKit's auth scheme: requests to `<server>/rest/<action>.view` (Ampache uses
  its Subsonic-compatible endpoint `<server>/rest/server.php`), salted token auth
  (`t = md5(password + salt)`, `s = salt`) with automatic fallback to legacy
  plain-password auth (`p`) when the server rejects tokens (e.g. LDAP-backed
  accounts answering Subsonic error 41) — mirroring AmperfyKit's auto-detection.
  Responses as JSON. Any subpath in the server URL is preserved (servers behind
  reverse proxies / tunnels). Supports custom HTTP headers (e.g. Cloudflare Access)
  for data requests.
- **`Api/WatchApi.swift`** — facade the SwiftUI views call.
- **`Services/WatchConnectivityReceiver.swift`** — receives credentials pushed from
  the phone, stores them, re-authenticates.
- **`Services/WatchCredentialStore.swift`** — Keychain storage (watch-local).
  (App Groups cannot share data between iOS and watchOS, so credentials are
  delivered via WatchConnectivity, not a shared container.)
- **`Services/WatchPlayerService.swift`** — AVPlayer streaming + offline file
  playback, queue, now-playing info, remote commands.
- **`Services/WatchDownloadService.swift`** — downloads to the watch caches dir.
- **`Views/`** — SwiftUI screens. Navigation mirrors the iOS app adapted to the
  watch: a single `NavigationStack` rooted at **Home** (menu rows for Search,
  Recently Added, Playlists, Artists, Albums, Podcasts, Downloads), which open
  per-category lists that load on demand. While music plays, Home shows a
  mini-player row; starting a song anywhere pushes **Now Playing**. The player
  screen puts artwork + titles on one row, shows remaining time, and uses the
  Digital Crown for volume (with a transient HUD); a secondary row offers ±15s
  seek, download toggle, and the Up Next sheet, which hosts the shuffle and
  repeat (off/all/one) toggles above the current queue. The player service keeps
  shuffle state across new queues and wraps/skips according to repeat mode; rapid
  button presses are coalesced so only one track load is in flight at a time.

## Building

Open `Amperfy.xcodeproj` and select the **Amperfy** scheme. The watch target is
implicitly built and embedded by the iOS target — you do not need a separate
scheme for the watch. To work on the watch target in isolation, create a scheme
targeting `Amperfy Watch` with a watchOS Simulator destination.

From the command line (iOS simulator, no signing — this also builds and embeds
the watch):

```sh
xcodebuild -project Amperfy.xcodeproj -scheme Amperfy \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

From the command line (watchOS simulator, no signing):

```sh
xcodebuild -project Amperfy.xcodeproj -target "Amperfy Watch" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=latest' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## What you must set up in Xcode (for TestFlight)

The watch app is an **independent app with a companion** (the iOS Amperfy app). For
WatchConnectivity account provisioning to work, the watch app's companion bundle id
must match the iOS app's bundle id, and both apps must be installed on paired
devices under the **same Apple Developer team**.

1. **Set your Development Team.** In Xcode, select both targets (*Amperfy* and
   *Amperfy Watch*) → *Signing & Capabilities* → check *Automatically manage
   signing* → select your personal team.

2. **Bundle IDs.** Defaults use the placeholder `com.amberfox.amperfy.*` prefix.
   Change all four consistently:
   - iOS app target: `PRODUCT_BUNDLE_IDENTIFIER` → `com.yourname.amperfy`
   - Watch target: `PRODUCT_BUNDLE_IDENTIFIER` → `com.yourname.amperfy.watchkitapp`
   - Watch target: `WK_COMPANION_APP_BUNDLE_IDENTIFIER` → `com.yourname.amperfy`
     (must equal the iOS app's bundle id)
   - `AmperfyKit` framework target: `PRODUCT_BUNDLE_IDENTIFIER` →
     `com.yourname.amperfy.AmperfyKit`
   - `AmperfyKitTests` target: `PRODUCT_BUNDLE_IDENTIFIER` →
     `com.yourname.amperfy.AmperfyKitTests`
   - `Amperfy/Info.plist` → `BGTaskSchedulerPermittedIdentifiers[0]` and
     `CFBundleURLName` to match the new iOS bundle id
   - `Amperfy/AppDelegate.swift` → `refreshTaskId` to match the BG task id above

3. **Register the App IDs** in your Apple Developer account (or let Xcode's
   automatic signing create them): the iOS app id and the watch app id.
   WatchConnectivity works without any special capability/entitlement.

4. **App Store Connect.** Create an App record for the watch app (and for the iOS
   app if you don't already have one). For TestFlight you need at least one App
   record per bundle id you upload.

5. **Archive & upload.** Select *Amperfy* scheme → *Generic iOS Device* destination
   → *Product → Archive* → *Distribute App → TestFlight & App Store*. The single
   archive contains both the iOS `.app` and the embedded watch `.app`, and a single
   upload delivers both.

6. **Install both on paired devices.** Install the iOS app (with the new
   WatchConnectivity provisioning) on your iPhone, and the watch app on a paired
   Apple Watch, both via TestFlight. Log in on the iPhone — credentials are pushed to
   the watch automatically. The watch can then stream/download directly and play
   downloads offline.

> WatchConnectivity between a standalone watch app and a separately-installed iOS app
> is supported for independent watch apps. If `isCompanionAppInstalled` ever reports
> false despite both being installed, test on real hardware (the simulator is
> unreliable for this) and confirm `WKCompanionAppBundleIdentifier` exactly matches
> the iOS app's bundle id and both share the same team.

## Known limitations (v1)

- The watch speaks the **Subsonic API**. Ampache servers are reached via Ampache's
  Subsonic-compatible endpoint (`/rest/server.php`), which works for browsing,
  search, streaming, and downloads. Ampache-only features not in the Subsonic API
  aren't exposed.
- **Streaming to a Cloudflare-Access-protected server** won't work on the watch:
  watchOS has no public API to attach custom HTTP headers to an `AVURLAsset`, so only
  the auth-in-URL path is used. Data requests (downloads, search) do send the custom
  headers, so downloads from such servers still work.
- "Recently Played" surfaces the newest-added songs (Subsonic has no
  recently-played call without scrobbling).
- Swift language version on the watch target is set to 5.0 (`SWIFT_VERSION = 5.0`,
  `SWIFT_STRICT_CONCURRENCY = minimal`); a Swift 6 strict-concurrency pass is a
  follow-up.
