---
name: troubleshoot-webview-windows
description: Use when a Flutter Windows app using webview_flutter_windows misbehaves - a blank or frozen webview, initialize() failing with environment_creation_failed or webview_creation_failed, StateError or MissingPluginException, keyboard input stuck in the page or a text field, missing right-click context menus, popups not opening, stream events never arriving, cookies missing, blurry rendering, or Windows build failures around NuGet, WebView2 SDK, CMake, Visual Studio, or WebView2Loader.dll.
---

# Troubleshoot webview_flutter_windows

Diagnose by symptom, confirm the cause, then apply the narrowest fix. Many
"bugs" here are documented behaviors of the package or of WebView2 itself;
check this catalog before changing app code. Exact API and error-code tables:
`references/error-codes.md` in this skill directory.

## First, collect the facts

1. Package version from `pubspec.yaml` / `pubspec.lock`
   (`webview_flutter_windows`).
2. `flutter --version` (package needs Flutter >=3.44 / Dart >=3.12).
3. Windows version (needs Windows 10 1809+) and architecture.
4. `await WebviewController.getWebViewVersion()` - `null` means the WebView2
   Runtime is not installed.
5. The exact error: `PlatformException.code`, `StateError` message, or build
   log lines. Codes are listed in `references/error-codes.md`.

These are also exactly the fields the repo's bug-report form requires, so a
report that cannot be fixed locally is ready to file at
<https://github.com/omar-hanafy/webview_flutter_windows/issues>.

## Initialization failures

| Evidence | Cause | Fix |
| --- | --- | --- |
| `PlatformException(environment_creation_failed)` and `getWebViewVersion()` returns null | WebView2 Runtime missing | Install the Evergreen runtime; add startup detection UX (see `integrate-webview-windows`) |
| `environment_creation_failed` but runtime version is reported | User data folder locked or unwritable (two app versions sharing one folder, AV lock, or a custom `userDataPath` without write permission) | Point `initializeEnvironment(userDataPath: ...)` at a writable per-app folder; close other instances; default location is under `LocalAppData` |
| `PlatformException(environment_already_initialized)` | `initializeEnvironment` called while a controller is alive | Call it before creating any controller; it becomes callable again after the last controller is disposed (reference-counted environment) |
| `PlatformException(webview_creation_failed)` | Environment ok, controller creation failed (GPU/driver, exhausted resources) | Retry once; update graphics drivers; check `additionalArguments` for typos |
| `StateError: ... not initialized. Call initialize() first.` | Method called before `initialize()` completed | Await `initialize()`; gate UI on `controller.value.isInitialized` |
| `StateError: initialize() called after dispose` | Lifecycle bug in app code | Create a new controller instead of reusing a disposed one |
| `MissingPluginException` | Not running on Windows, or a test without channel mocks | Guard with `Platform.isWindows`; in tests use the `test-webview-windows` skill |

## Blank, frozen, or wrong-looking webview

| Evidence | Cause | Fix |
| --- | --- | --- |
| Widget area empty, no error | Controller not initialized yet (widget renders `SizedBox` until then) | Gate on `isInitialized`; rebuild (`setState`) after init completes |
| Headless controller: page JS runs but layout/size is zero | No bounds | Call `setSize(const Size(w, h))`; pages do not lay out with zero bounds |
| Frame frozen after `suspend()` | Suspended webviews stop rendering | Call `resume()` when visible again |
| Blurry or pixelated content | Custom `scaleFactor` (e.g. 1.0) disables high-DPI rendering | Leave `scaleFactor` unset; adjust `filterQuality` only when downscaling |
| Semi-transparent background renders opaque | WebView2 limitation: nonzero alpha is treated as opaque | Use fully transparent (`Colors.transparent`) or opaque colors |
| Whole app fails to show web content on Windows 10 pre-1809 | `Windows.Graphics.Capture` unavailable | Unsupported OS; require 1809+ |

## Keyboard and focus

The fork fixes upstream focus loss (issue 230); remaining reports are
usually the documented behavior:

| Evidence | Assessment | Action |
| --- | --- | --- |
| Typing goes to the page after clicking it | By design: the page owns real Win32 focus after a click | Click any Flutter widget or call `WebviewController.releaseFocus()` |
| Clicking Flutter UI does not return typing to Flutter | Should not happen in 1.x | Verify no leftover pre-1.0 focus workarounds intercept clicks (see `migrate-from-webview-windows` step 7); confirm package >=1.0.0 actually resolved in `pubspec.lock` |
| `controller.focus()` seems ignored | A Flutter text input owns primary focus; the grab is reverted by the enforced invariant | Unfocus the text input first, then call `focus()` |
| Tab cycles inside the page forever | Fixed in 1.x | Confirm the resolved version; report with repro if it persists |
| Window deactivates (gray title bar) when clicking the page | Upstream 0.x behavior | Migrate to 1.x (`migrate-from-webview-windows`) |

## Events and streams

- Events "never arrive": all streams are broadcast; events emitted while
  nobody listens are dropped. Subscribe before navigating.
- Streams "end unexpectedly": every stream emits `done` when the controller
  is disposed; a `done` right after an action means something disposed the
  controller.
- `webMessage` problems: see the `bridge-webview-windows` skill (JSON string
  vs object asymmetry, `onError`).

## Behavior differences that are configuration, not bugs

| Evidence | Cause | Fix |
| --- | --- | --- |
| No right-click context menu | Menus are **disabled by default** by this package | `await controller.setDefaultContextMenusEnabled(true)` (>=1.1.0) after `initialize()`, before the navigation that needs it; a page may still suppress its own menu |
| `target=_blank` / popups do nothing | `setPopupWindowPolicy(deny)` set, or expectation mismatch | Choose `allow` or `sameWindow` |
| No permission prompts (camera, mic, geolocation, clipboard) | No `permissionRequested` delegate on the `Webview` widget | Provide the delegate; return `none` to fall back to WebView2 defaults |
| Cookie list empty | `getCookies(uri)` scopes to the uri | Use `getCookies('')` for the full profile; check the expected domain/path |
| Session lost across app runs | Custom or changing user data folder | Keep a stable `userDataPath` (or the default) |

## Build and toolchain failures (Windows host)

| Log evidence | Cause | Fix |
| --- | --- | --- |
| `Failed to download nuget` / NuGet integrity check failed | Network blocks `dist.nuget.org` (the bootstrap is SHA-256 verified) | Install `nuget.exe` manually and add it to `PATH`; fix proxy/TLS interception |
| `NuGet install failed for Microsoft.Web.WebView2` | Registry/feed blocked | Same as above; corporate feeds must mirror `Microsoft.Web.WebView2` and `Microsoft.Windows.ImplementationLibrary` |
| CMake version error | CMake < 3.20 | Update Visual Studio 2022 (bundles a newer CMake) |
| C++ toolset/std errors in the app's own `windows/runner` code after upgrading | 1.x no longer propagates `cxx_std_20` to the app | Add `target_compile_features(${BINARY_NAME} PRIVATE cxx_std_20)` to the runner's CMakeLists.txt |
| Missing `WebView2Loader.dll` next to the exe | Broken/partial build output | `flutter clean; flutter build windows`; verify the plugin built (`webview_flutter_windows_plugin.dll` in the bundle) |
| MSVC not found | Visual Studio workload missing | Install VS2022 "Desktop development with C++" + Windows 10/11 SDK |

## Diagnostic moves

- `openDevTools()` opens the page's DevTools window: console errors, network
  failures, CSP blocks.
- Log everything cheaply while reproducing:
  `url`, `loadingState`, `onLoadError`, `title`, `onFocusChanged` listeners
  with `debugPrint`.
- `onLoadError` emitting `WebErrorStatus.unknown` on a newer runtime is the
  documented mapping for statuses this package version does not know yet.
- Reproduce in the package's own example app
  (`example/` in the repo, `flutter run -d windows`) to separate app code
  from package behavior.

## When it is really a package bug

Reduce to a minimal repro, gather the facts from "First, collect the facts",
and file with the repository's bug-report form (it asks for exactly those
fields plus an affected-area category). Do not include cookies, tokens, or
private URLs in the report.
