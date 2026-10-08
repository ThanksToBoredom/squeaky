# Squeaky

A native macOS cleaner, built in SwiftUI. Each module has its own full-bleed gradient window, an
icon sidebar, and a simple welcome → scan → results → review → done flow.

| Module | What it does |
| --- | --- |
| **Sweep** | Runs Cleanup, Applications and Declutter scans in parallel; **Run** cleans the junk and moves duplicate downloads to the Trash. |
| **Cleanup** | User caches, logs, Xcode junk, Trash, Mail attachments, broken downloads and package-manager caches. |
| **Applications** | Uninstaller (the app plus its `~/Library` support files, which you can expand and untick one by one), unused apps (not opened in 90 days), and leftovers from apps that are already deleted. |
| **Declutter** | Duplicates (size → partial hash → SHA-256), files over 100 MB, and downloads older than 90 days. |
| **Protection** | Malware scan using Apple's own XProtect definitions (see below). |
| **Performance** | A live dashboard modelled on [PureMac](https://github.com/momenbasel/PureMac)'s: CPU, memory and disk meters; your apps and processes by CPU or memory (helpers grouped with their app); launch agents and daemons with their triggers (your own agents can be removed: unloaded, then moved to the Trash; system-wide ones link to Login Items & Extensions, where macOS switches them off reversibly, or to uninstalling their app); local snapshots, with Time Machine ones deletable via `tmutil`. Nothing is "optimised" behind your back. |

## Safety

- Caches, logs, Xcode junk and Trash contents are **deleted permanently**. Everything else (apps, leftovers, your own files) is **moved to the Trash**.
- Every clean asks for confirmation first.
- `FileUtils.isSafeToRemove` refuses anything outside your home folder (other than `/Applications/*.app`), as well as the well-known folders themselves.
- Apps that are running are skipped. Leftovers, large files and old downloads start **unselected**.

## What the uninstaller removes

Everything in `~/Library` that matches the app by:

- its bundle ID, or the bundle IDs of helpers and extensions it ships (`PlugIns`, `XPCServices`,
  `LoginItems`, `LaunchServices`, `Helpers`), exactly or at a dot boundary, also behind a `group.` or
  team-ID prefix;
- an app group from its code-signing entitlements (Apple's own groups excluded);
- the owner recorded inside UUID-named containers;
- a launch agent whose `Program` lives inside the app, or whose label matches;
- a plug-in's own bundle ID, or the app's exact name.

Files that more than one installed app claims (two copies of the same app, a vendor's shared folder) are
kept. The app's login items and bundled launch agents are stopped before it's moved to the Trash.

Searched folders:

Application Support, Caches, Preferences (incl. `ByHost`), Containers, Group Containers, Saved Application
State, Logs, HTTPStorages, WebKit, Cookies, Application Scripts, LaunchAgents (unloaded first), Internet
Plug-Ins, QuickLook, Spotlight, PreferencePanes, Services, and crash/hang reports in
`Logs/DiagnosticReports`.

System-wide files (`/Library/...`, launch daemons, privileged helpers, package receipts) are **not**
removed yet; that needs root, see *Open work* below. Instead, apps are flagged when they have system
parts (launch items in `/Library` associated with the app via `AssociatedBundleIdentifiers`, its
program path or bundle IDs, plus the privileged helpers they run), and the confirmation offers the
vendor's own uninstaller when one is found. Apps owned by root (installed by a package) are moved to
the Trash by Finder, which asks for an administrator password; the path is passed to `osascript` as an
argument, never spliced into the script.

## Permissions

On first launch Squeaky asks for **Full Disk Access** (it can't be requested programmatically; the card
links straight to the right System Settings pane). While the card is open Squeaky re-checks every 1.5 s,
offers **Relaunch Squeaky** once you've been sent to System Settings, and confirms when access is on.
The shield at the bottom of the sidebar shows the current state and reopens the card.

macOS ties the grant to the app's code signature. Ad-hoc signatures change on every build, so run
`scripts/create-signing-cert.sh` once: it creates a self-signed "Squeaky Local Signing" certificate in your
login keychain, and `build-app.sh` signs with it from then on.

## Build & run

Requires macOS 15+ and Swift 6 (the Command Line Tools are enough).

```sh
scripts/build-app.sh          # release build → build/Squeaky.app
open build/Squeaky.app
```

### Sharing a build

`scripts/package.sh` makes a release build and wraps it in `dist/Squeaky.dmg` (Apple Silicon only).
It's signed with the local certificate, not an Apple Developer ID, so on another Mac Gatekeeper blocks
the first launch: open it once, then choose **Open Anyway** in System Settings → Privacy & Security.
Avoiding that needs a paid Apple Developer account (Developer ID signing plus notarization).

### Toolchain notes

- On the macOS 27 SDK, `@State` is a macro whose plugin only ships with Xcode. The code uses
  `@ViewState` (see `ViewState.swift`), a thin `DynamicProperty` wrapper around `State`.
- The script builds with `--build-system native` because the default backend fails to initialise
  with the Command Line Tools.

### Snapshot mode (development)

Steps are `;`-separated: a module name (`sweep`, `cleanup`, `applications`, `declutter`, …) optionally
followed by `:scan`, `:review[:category]`, `:dump`, `:demo`, `:demo-real` (throwaway folders in
~/Library/Caches that really get deleted) or `:clean[:alert|:click|:cancel]`, plus `permissions[:granted]`,
`sweep-run` and `celebrate`. `SQUEAKY_SNAPSHOT_ANIMATE=1` keeps animations on, and (debug builds)
`SQUEAKY_SLOW_CLEAN=<seconds>` makes each clean take longer, for testing the cleaning screens. Most steps render the window with `cacheDisplay`, which can't see Core Animation particles;
`celebrate` instead records a frame sequence with ScreenCaptureKit, so launch with
`open -n --env SQUEAKY_SNAPSHOT_DIR=… build/Squeaky.app` and give Squeaky Screen Recording permission.

Renders the window to PNGs without needing Screen Recording permission:

```sh
SQUEAKY_SNAPSHOT_DIR=/tmp/shots SQUEAKY_SNAPSHOT_SCRIPT="sweep:scan;cleanup;cleanup:review:caches" \
SQUEAKY_SNAPSHOT_QUIT=1 build/Squeaky.app/Contents/MacOS/Squeaky
```

## Open work

- **System-wide leftovers** (`/Library/Application Support`, `LaunchDaemons`, `PrivilegedHelperTools`,
  receipts) and root-owned apps need administrator rights. Options: a per-removal password prompt, or a
  privileged helper registered with `SMAppService` (one-time approval, but should only ship with a
  Developer ID signature so the helper can verify who's calling it).

## Credits

The app icon is drawn by `scripts/make-icon.swift` from `Resources/Icon/guinea-pig-3d.png`, our own
3D guinea pig (transparent background). `Resources/Icon/guinea-pig.svg` is the flat version of the same
design. After changing the artwork, run `swift scripts/make-icon.swift Resources/AppIcon.icns`.

The take-away illustration on the App Leftovers card uses SVGs from Microsoft's
[Fluent Emoji](https://github.com/microsoft/fluentui-emoji) (MIT licence, bundled as
`Resources/Art/FluentEmoji-LICENSE.txt`). `french_fries_empty.svg` and `fry_single.svg` are edited
from Fluent's `french_fries_color.svg` (most fries removed / one fry extracted).

The Applications and Protection module icons are `apps` and `radar` (filled) from [Tabler Icons](https://tabler.io/icons)
(MIT licence, bundled as `Resources/Art/TablerIcons-LICENSE.txt`). Any symbol name starting with `svg:`
is loaded from `Resources/Art` by `SymbolImage`, so other SF Symbols can be swapped the same way.

## Protection (malware scan)

Squeaky doesn't ship or download signatures. It reads Apple's XProtect definitions from the system at
scan time (`/var/protected/xprotect/…` on macOS 15+, else `/Library/Apple/…/XProtect.bundle`), which
Apple updates in the background, and runs them with a vendored copy of
[libyara](https://github.com/VirusTotal/yara) 4.5.8 (BSD-3, `Sources/CYara`, see `VENDORED.md`).

| Check | Source |
|---|---|
| YARA rules over app executables, launch-item programs, and executables/scripts in Downloads, Desktop, Documents, Application Support, /Users/Shared and temp folders | `XProtect.yara`, `XPScripts.yr` |
| Revoked code hashes and developer teams | `gk.db` (Gatekeeper blocklist) |
| Blocked Safari extensions inside apps | `XProtect.meta.plist` |
| Launch items whose program is missing, unsigned or in a hidden/temp folder (review only, not called malware) | heuristics |

Threats go to the Trash with the launch items that start them. No root is needed; files only root can
read are skipped, and files over 150 MB are skipped. Not covered yet: XProtect's legacy
`XProtect.plist` patterns, system LaunchDaemons removal (needs admin), real-time protection.
Online catalogs were evaluated and left out for now: MalwareBazaar needs an API key and restricts
commercial use, ClamAV signatures are GPL, and VirusTotal's free API forbids use in products.

Debug builds accept `SQUEAKY_TEST_RULE=1`, which adds a rule matching files containing
`SQUEAKY-YARA-SELFTEST`, for testing detection end to end without real malware.
