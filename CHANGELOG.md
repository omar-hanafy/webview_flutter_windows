## 1.0.0

First stable release of `webview_flutter_windows`
([omar-hanafy/webview_flutter_windows](https://github.com/omar-hanafy/webview_flutter_windows)),
a maintained fork/rebuild of upstream `webview_windows` `0.4.0` including all
upstream changes up to `ed81bbe`. This API is the maintained baseline going
forward: any future breaking change will come with a major version bump.

This release contains **breaking changes**. See the
[migration guide](https://github.com/omar-hanafy/webview_flutter_windows/blob/main/migration_guide.md)
for step-by-step upgrade instructions.

### Breaking changes

* Published under the new package name `webview_flutter_windows`; migrate
  dependencies and imports from `webview_windows`.
* Requires Dart 3.12+ / Flutter 3.44+.
* All `WebviewController` event streams are now broadcast streams: multiple
  listeners are allowed, and events emitted while nobody listens are dropped.
* `WebErrorStatus` values are renamed to lowerCamelCase
  (`WebErrorStatusTimeout` -> `WebErrorStatus.timeout`); the underlying
  indexes are unchanged.
* Calling controller methods before `initialize()` completes now throws a
  `StateError` with an actionable message instead of crashing in release
  builds.
* `initialize()` throws a `StateError` when called on a disposed controller,
  and completes with the underlying error on any failure (previously some
  failures left the controller, `ready`, and `dispose()` hanging forever).
* The internal `getButton` helper is no longer exported.

### Window focus

Fixes the long-standing focus loss issue
([jnschulze/flutter-webview-windows#230](https://github.com/jnschulze/flutter-webview-windows/issues/230)):

* Clicking a webview no longer deactivates the host window (gray title bar,
  dead keyboard shortcuts).
* Clicking Flutter UI outside a webview hands keyboard focus back to Flutter
  automatically, and pressing `Tab` past the page's last focusable element
  moves focus back to Flutter instead of cycling inside the page forever.
* Enforced invariant: while a Flutter text input owns Flutter focus, no
  webview keeps native keyboard focus. A `TextField` gaining focus while the
  page holds the keyboard - or any code path grabbing native focus while a
  text input is focused - results in focus being handed back to Flutter
  immediately, in both event orders.
* New API: `WebviewController.focus()`, `WebviewController.releaseFocus()`,
  the `onFocusChanged` stream, and `hasNativeFocus`.

### New features

* Cookie management: `getCookies()`, `setCookie()`, and `deleteCookies()`
  with a typed `WebviewCookie` model (expiry, SameSite, secure, HTTP-only),
  alongside the existing `clearCookies()`.
* Reference-counted environment lifecycle: the WebView2 environment is
  released when the last controller is disposed, so
  `initializeEnvironment()` can be called again - e.g. with a different
  `userDataPath` - without restarting the app.
* Headless usage: a controller can be driven without a `Webview` widget for
  background pages; the new `setSize()` gives the invisible page real bounds
  so it performs layout.

### Improvements

* `initialize()` is re-entrant: concurrent calls join the in-flight attempt,
  and a failed attempt can be retried.
* `dispose()` is idempotent, safe in every lifecycle state, and closes all
  event streams.
* Load-error statuses reported by a newer WebView2 runtime than this package
  knows map to `WebErrorStatus.unknown` instead of throwing a `RangeError`.
* The `Webview` widget accepts a `key` and resolves its device pixel ratio
  per view (multi-window safe).
* Full dartdoc coverage of the public API.

### Native fixes

* Fixed inverted success reporting for `addVirtualHostNameMapping` /
  `removeVirtualHostNameMapping` (success was reported as failure).
* Fixed `dispose` silently leaking the native webview instance for texture
  ids that fit in 32 bits.
* Fixed COM reference leaks and latent use-after-frees in touch pointer
  events, permission requests, environment creation, WinRT factory access,
  and native string getters.
* Non-ASCII `additionalArguments` now reach Chromium as proper UTF-8 instead
  of being mangled.
* Malformed method channel arguments produce an error result instead of
  terminating the process, and all nullable native strings are converted
  null-safely.
* Webview creation failures are surfaced as errors instead of returning a
  silent, dead instance.

### Toolchain

* WebView2 SDK `1.0.1210.39` -> `1.0.3967.48`, WIL `1.0.220914.1` ->
  `1.0.260126.7`.
* The plugin builds as C++23 and no longer forces a C++ language level onto
  the consuming app; the CMake minimum is 3.20.
* The NuGet bootstrap is SHA-256 verified and dependencies are installed at
  configure time, so first builds no longer race the imported `.targets`.

## 0.4.0

* Enable MSVC coroutine support ([#278](https://github.com/jnschulze/flutter-webview-windows/pull/278))
* Enable scrolling with trackpad ([#274](https://github.com/jnschulze/flutter-webview-windows/pull/274))

## 0.3.0

* Add full-screen support ([#189](https://github.com/jnschulze/flutter-webview-windows/pull/189))
* Make `loadingState` a broadcast stream ([#193](https://github.com/jnschulze/flutter-webview-windows/pull/193))
* Add `getWebViewVersion()` method ([#197](https://github.com/jnschulze/flutter-webview-windows/pull/197))
* Fix string casting of paths that may contain Unicode characters ([#199](https://github.com/jnschulze/flutter-webview-windows/pull/199))
* Add high-DPI screen support ([#203](https://github.com/jnschulze/flutter-webview-windows/pull/203))
* Add `setZoomFactor` ([#214](https://github.com/jnschulze/flutter-webview-windows/pull/214))
* Fix example ([#215](https://github.com/jnschulze/flutter-webview-windows/pull/215))
* Fix Visual Studio 17.6 builds ([#252](https://github.com/jnschulze/flutter-webview-windows/pull/252))

## 0.2.2

* Remove `libfmt` dependency in favor of C++20 `std::format`
* Enable D3D texture bridge by default
* Make `executeScript` return the script's result

## 0.2.1

* Add `WebviewController.addScriptToExecuteOnDocumentCreated` and `WebviewController.removeScriptToExecuteOnDocumentCreated`
* Add `WebviewController.onLoadError` stream
* Change `WebviewController.webMessage` stream type from `Map<dynamic, dynamic>` to `dynamic`
* Add virtual hostname mapping support 
* Add multi-touch support

## 0.2.0

* Fix Flutter 3.0 null safety warning in example
* Bump WebView2 SDK version to `1.0.1210.3`
* Add an option for limiting the FPS
* Change data directory base path from `RoamingAppData` to `LocalAppData`

## 0.1.9

* Fix Flutter 3.0 compatibility

## 0.1.8

* Prefix CMake build target names to prevent collisions with other plugins

## 0.1.7

* Add method for opening DevTools
* Update `TextureBridgeGpu`
* Update `libfmt` dependency

## 0.1.7-dev.2

* Ensure Flutter apps referencing `webview_windows` still work on Windows 8.

## 0.1.7-dev.1

* Remove windowsapp.lib dependency

## 0.1.6

* Improve WebView creation error handling

## 0.1.5

* Fix a potential crash during WebView creation

## 0.1.4

* Improve error handling for Webview environment creation

## 0.1.3

* Stability fixes

## 0.1.2

* Unregister method channel handlers upon WebView destruction

## 0.1.1

* Fix unicode string conversion in ExecuteScript and LoadStringContent
* Load CoreMessaging.dll on demand

## 0.1.0

* Fix a string conversion issue
* Add an option for controlling popup window behavior
* Update Microsoft.Web.WebView2 and Microsoft.Windows.ImplementationLibrary

## 0.0.9

* Fix resizing issues
* Add preliminary GpuSurfaceTexture support

## 0.0.8

* Don't rely on AVX2 support
* Add history controls
* Add suspend/resume support
* Add support for disabling cache, clearing cookies etc.

## 0.0.7

* Add support for handling permission requests
* Allow setting the background color
* Automatically download nuget

## 0.0.6

* Fix mousewheel event handling
* Make text selection work
* Add method for setting the user agent
* Add support for JavaScript injection
* Add support for JSON message passing between Dart and JS
* Fix WebView disposal

## 0.0.5

* Fix input field focus issue

## 0.0.4

* Minor cleanup

## 0.0.3

* Add support for additional cursor types

## 0.0.2

* Add support for loading string content

## 0.0.1

* Initial release
