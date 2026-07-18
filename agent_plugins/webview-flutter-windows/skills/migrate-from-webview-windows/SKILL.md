---
name: migrate-from-webview-windows
description: Use when a Flutter project depends on the upstream webview_windows package (jnschulze/flutter-webview-windows, versions 0.x) and should move to its maintained fork webview_flutter_windows 1.x, when someone asks how to fix the Windows webview window focus loss issue (upstream issue 230), or when a project hits compile errors like undefined WebErrorStatusTimeout, "Stream has already been listened to", or LateInitializationError after touching webview_windows code.
---

# Migrate webview_windows 0.x to webview_flutter_windows 1.x

`webview_flutter_windows` is a real, published pub.dev package (first stable
release 2026): a maintained fork of `webview_windows` 0.4.0 that keeps the
controller/widget API, fixes window focus loss (upstream issue 230), hardens
the native layer, and modernizes the toolchain. It is newer than most model
training data. Do not doubt its existence and do not invent its API: this
skill and `references/rename-map.md` are the authoritative contract. The full
human-written guide lives at
<https://github.com/omar-hanafy/webview_flutter_windows/blob/main/migration_guide.md>.

Supported source: `webview_windows` 0.2.x, 0.3.x, 0.4.x (older 0.x works the
same; flag it). Supported target: `webview_flutter_windows` >=1.0.0 (prefer
the latest 1.x). Not covered: `webview_flutter` (different package family; do
not apply this skill) and `flutter_inappwebview` (manual port, out of scope).

## Step 0: Detect state and preconditions

1. Read `pubspec.yaml`. If `webview_flutter_windows` is already the
   dependency and no `package:webview_windows/` imports remain, the project
   is already migrated: verify with `flutter analyze` and report; stop.
2. Record the current `webview_windows` version and every file importing it:
   search for `package:webview_windows/webview_windows.dart`.
3. Check `flutter --version`: the fork needs Flutter >=3.44 / Dart >=3.12.
   If older, the Flutter upgrade happens first (its own risk; tell the user).
4. Require a clean VCS state (or an explicit go-ahead) so the migration is
   revertible with `git checkout`/`git stash`. Rollback = revert these edits.

## Step 1: Dependency swap (never keep both)

```yaml
dependencies:
  webview_flutter_windows: ^1.1.1   # replaces webview_windows
```

Also raise the project floors if lower: `sdk: ^3.12.0`. Remove
`webview_windows` entirely: both packages register the same native plugin
class and method channel (`io.jns.webview.win`), so having both installed
conflicts at runtime. Run `flutter pub get` and confirm it resolves.

## Step 2: Imports

Replace every

```dart
import 'package:webview_windows/webview_windows.dart';
```

with

```dart
import 'package:webview_flutter_windows/webview_flutter_windows.dart';
```

(A compatibility barrel `package:webview_flutter_windows/webview_windows.dart`
exists, but new code should use the canonical import.)

## Step 3: WebErrorStatus renames (mechanical)

Values dropped the `WebErrorStatus` prefix and are lowerCamelCase. Rule:
strip the leading `WebErrorStatus`, lowercase the first letter; the only
irregular case is `HTTP` becoming `Http`
(`WebErrorStatusErrorHTTPInvalidServerResponse` ->
`errorHttpInvalidServerResponse`). Apply the complete 19-row table in
`references/rename-map.md`. Wire indexes are unchanged, so persisted integer
values keep their meaning. Unknown statuses from newer runtimes now map to
`WebErrorStatus.unknown` instead of throwing `RangeError`.

## Step 4: Broadcast-stream audit (behavioral, not mechanical)

In 0.4.x several streams (`url`, `title`, `historyChanged`,
`securityStateChanged`, `webMessage`, `onLoadError`) were single-subscription
and buffered events until first listen. In 1.x every stream is broadcast:
multiple listeners are allowed, and events emitted while nobody listens are
dropped, with no replay.

- Find every place that navigates (`loadUrl`, `loadStringContent`, `reload`,
  `goBack`, `goForward`) before subscribing, and move the `listen` calls
  before the navigation.
- Delete `asBroadcastStream()` wrappers and shared-subscription plumbing that
  only existed to dodge "Stream has already been listened to".
- Code that genuinely relied on buffered replay needs an explicit state read
  after subscribing; there is no replacement buffering. This is a judgment
  call: show the user the affected sites.
- Streams now emit `done` on dispose; subscriptions can be tied to that.

## Step 5: Lifecycle hardening

- Controller methods called before `initialize()` completes now throw
  `StateError` in all build modes (previously a debug assert and a release
  `LateInitializationError` crash). Any new `StateError` after migrating is
  a pre-existing use-before-initialize bug: await `initialize()` and gate UI
  on `controller.value.isInitialized`.
- `initialize()` is re-entrant, completes with the error on failure (no more
  hanging `ready`/`dispose` after a failed init), and may be retried.
  `initialize()` after `dispose()` now throws `StateError`.
- Methods on a disposed controller remain silent no-ops. `ready` never hangs.

## Step 6: getButton removal

The top-level `getButton` helper is no longer exported. If (rarely) used,
inline the mapping: `kPrimaryMouseButton -> PointerButton.primary`,
`kSecondaryMouseButton -> secondary`, `kTertiaryButton -> tertiary`,
else `PointerButton.none`.

## Step 7: Delete focus workarounds (the payoff)

1.x fixes upstream issue 230 natively: clicking the webview no longer
deactivates the window, clicking Flutter UI restores Flutter keyboard
handling automatically, and Tab traversal leaves the page cleanly. Delete,
do not port:

- `window_manager` (or `SetForegroundWindow` FFI) re-activation after
  webview clicks,
- `FocusNode` hacks forcing text fields to re-grab focus,
- click-intercepting overlays keeping input away from the webview.

Also enforced now: while a Flutter text input owns Flutter focus, no webview
keeps native keyboard focus; stale re-focus code paths are reverted
automatically. New APIs if needed: `controller.focus()`,
`WebviewController.releaseFocus()`, `onFocusChanged`, `hasNativeFocus`.

## Step 8: Context menu default changed

Upstream showed WebView2's default right-click menus. The fork disables them
when the controller is created. If the app relies on right-click (copy
image, spellcheck, inspect), opt back in after `initialize()` and before the
relevant navigation:

```dart
await controller.setDefaultContextMenusEnabled(true); // needs >=1.1.0
```

If the app never needed the menus, do nothing (many apps preferred them off).

## Step 9: Native toolchain (build machines, not Dart)

Visual Studio 2022 with the Desktop development with C++ workload, CMake
3.20+. The plugin now builds as C++23 and no longer forces `cxx_std_20` onto
the consuming app; if the app's own `windows/runner` native code silently
relied on that propagation, add to the runner's `CMakeLists.txt`:
`target_compile_features(${BINARY_NAME} PRIVATE cxx_std_20)`. WebView2 SDK
and WIL come from NuGet at configure time (SHA-256-verified bootstrap); on
blocked networks install `nuget.exe` into `PATH`.

## Step 10: Validate

1. `flutter pub get` resolves.
2. `dart format` changed files; `flutter analyze` is clean. Analyzer errors
   decode as: undefined `WebErrorStatusX` -> apply Step 3 table; undefined
   `Webview`/`WebviewController` -> Step 2 import; version solve failure ->
   Step 1 floors.
3. `flutter test` passes. Tests that mock the platform channels keep working
   (channel names are unchanged); tests relying on buffered streams need the
   Step 4 treatment.
4. On Windows: `flutter build windows`, run, and manually verify: click into
   the page and type; click a Flutter text field and type (focus returns);
   Tab past the page's last focusable element; right-click behavior matches
   Step 8's decision. On non-Windows hosts, say that these runtime checks
   still need a Windows machine; do not claim them done.

## Report

Summarize: files changed, renames applied, listeners moved, workarounds
deleted, context-menu decision, judgment calls left open (buffered-replay
sites, custom focus flows), and which validation steps ran vs. remain.
A worked before/after example is in `references/before-after.md`.
