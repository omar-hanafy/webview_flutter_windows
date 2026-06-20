# Migration guide

## Upgrading from `webview_windows` 0.4.x to `webview_flutter_windows` 1.0.0

Version 1.0.0 is the first stable release of
[omar-hanafy/webview_flutter_windows](https://github.com/omar-hanafy/webview_flutter_windows),
a maintained fork of
[jnschulze/flutter-webview-windows](https://github.com/jnschulze/flutter-webview-windows).
It includes everything released by upstream up to commit `ed81bbe`, fixes the
window focus loss issue
([upstream #230](https://github.com/jnschulze/flutter-webview-windows/issues/230)),
and modernizes both the Dart and the native layers.

Most apps only need steps 1 to 3. The remaining sections cover behavior
changes that matter only if your code relied on the old semantics, plus the
focus workarounds you can now delete.

1. [Package name and import](#1-package-name-and-import)
2. [New SDK floors](#2-new-sdk-floors)
3. [`WebErrorStatus` renames](#3-weberrorstatus-renames)
4. [Event streams are now broadcast](#4-event-streams-are-now-broadcast)
5. [`StateError` instead of crashes](#5-stateerror-instead-of-crashes)
6. [`initialize()`, `ready`, and `dispose()`](#6-initialize-ready-and-dispose)
7. [`getButton` was removed](#7-getbutton-was-removed)
8. [Focus handling is built in now](#8-focus-handling-is-built-in-now)
9. [Native toolchain notes](#9-native-toolchain-notes)

---

### 1. Package name and import

Replace the dependency name:

```yaml
dependencies:
  webview_flutter_windows: ^1.0.0
```

Use the new canonical library import:

```dart
import 'package:webview_flutter_windows/webview_flutter_windows.dart';
```

The compatibility barrel
`package:webview_flutter_windows/webview_windows.dart` remains available, but
new code should use `webview_flutter_windows.dart`.

### 2. New SDK floors

The package now requires:

```yaml
environment:
  sdk: ^3.12.0
  flutter: ">=3.44.0"
```

The Windows requirements are unchanged: Windows 10 1809 or newer at runtime,
and the [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)
must be installed on the user's machine.

### 3. `WebErrorStatus` renames

The `WebErrorStatus` values dropped their redundant prefix and follow standard
Dart `lowerCamelCase`. The underlying indexes (the native wire format) are
unchanged, so persisted integer values keep their meaning.

The rule: remove the leading `WebErrorStatus` and lowercase the first letter.
The only name that is not purely mechanical is the HTTP one (`HTTP` became
`Http`).

| 0.4.x | 1.0.0 |
| --- | --- |
| `WebErrorStatusUnknown` | `unknown` |
| `WebErrorStatusCertificateCommonNameIsIncorrect` | `certificateCommonNameIsIncorrect` |
| `WebErrorStatusCertificateExpired` | `certificateExpired` |
| `WebErrorStatusClientCertificateContainsErrors` | `clientCertificateContainsErrors` |
| `WebErrorStatusCertificateRevoked` | `certificateRevoked` |
| `WebErrorStatusCertificateIsInvalid` | `certificateIsInvalid` |
| `WebErrorStatusServerUnreachable` | `serverUnreachable` |
| `WebErrorStatusTimeout` | `timeout` |
| `WebErrorStatusErrorHTTPInvalidServerResponse` | `errorHttpInvalidServerResponse` |
| `WebErrorStatusConnectionAborted` | `connectionAborted` |
| `WebErrorStatusConnectionReset` | `connectionReset` |
| `WebErrorStatusDisconnected` | `disconnected` |
| `WebErrorStatusCannotConnect` | `cannotConnect` |
| `WebErrorStatusHostNameNotResolved` | `hostNameNotResolved` |
| `WebErrorStatusOperationCanceled` | `operationCanceled` |
| `WebErrorStatusRedirectFailed` | `redirectFailed` |
| `WebErrorStatusUnexpectedError` | `unexpectedError` |
| `WebErrorStatusValidAuthenticationCredentialsRequired` | `validAuthenticationCredentialsRequired` |
| `WebErrorStatusValidProxyAuthenticationRequired` | `validProxyAuthenticationRequired` |

```dart
// 0.4.x
if (status == WebErrorStatus.WebErrorStatusTimeout) { ... }

// 1.0.0
if (status == WebErrorStatus.timeout) { ... }
```

Related behavior change: when a newer WebView2 runtime reports a status this
package does not know yet, `onLoadError` now emits `WebErrorStatus.unknown`
instead of crashing the event handler with a `RangeError`.

### 4. Event streams are now broadcast

In 0.4.x, `url`, `title`, `historyChanged`, `securityStateChanged`,
`webMessage`, and `onLoadError` were single-subscription streams. In 1.0.0
every controller stream is a broadcast stream. Two things follow from that:

**Multiple listeners are now allowed.** Code that worked around the
"Stream has already been listened to" `StateError` (sharing one subscription,
calling `asBroadcastStream()`) can be simplified.

**Events emitted while nobody listens are dropped.** Single-subscription
streams buffer events until the first listener arrives; broadcast streams do
not. If you navigated first and subscribed later, you previously received the
buffered events on subscribe. Now you must subscribe before triggering the
work:

```dart
// 0.4.x - worked because the url stream buffered events:
await controller.loadUrl('https://flutter.dev');
controller.url.listen(handleUrl); // received the buffered URL change

// 1.0.0 - subscribe first:
controller.url.listen(handleUrl);
await controller.loadUrl('https://flutter.dev');
```

All streams also emit `done` when the controller is disposed, so
subscriptions can be tied to the controller's lifetime.

### 5. `StateError` instead of crashes

Calling any controller method before `initialize()` has completed used to
fail an `assert` in debug builds and crash with a `LateInitializationError`
in release builds. It now throws a `StateError` with an actionable message in
all build modes:

```dart
final controller = WebviewController();
await controller.loadUrl('...');
// 1.0.0: StateError: WebviewController is not initialized.
//        Call initialize() first.
```

If you see this error after upgrading, your code had a latent
use-before-initialize bug. The fix is the same as it always was: await
`initialize()` before using the controller, and gate UI on
`controller.value.isInitialized`.

Methods called on a *disposed* controller are unchanged: they remain silent
no-ops (and return `null` where applicable).

### 6. `initialize()`, `ready`, and `dispose()`

The controller lifecycle is hardened. None of this requires code changes in a
correct app, but the observable behavior differs:

* **`initialize()` is re-entrant.** Concurrent calls join the in-flight
  initialization instead of racing a second native instance into existence.
  Calling it again after success is a no-op.
* **Failures complete the future.** Any initialization failure (including a
  `MissingPluginException` when the native side is absent) completes the
  returned future with that error. In 0.4.x, non-`PlatformException` failures
  left the internal completer hanging, which made `ready` and a later
  `dispose()` await forever. A failed attempt can now be retried by calling
  `initialize()` again.
* **`initialize()` after `dispose()` throws a `StateError`.** Previously it
  silently returned.
* **`ready` never hangs.** It completes on successful initialization and also
  when the controller is disposed before ever initializing. After awaiting
  it, check `value.isInitialized` if you need to distinguish the two.
* **`dispose()` is idempotent and safe in every state**: before
  initialization, during initialization (it awaits the in-flight attempt so a
  concurrently created native instance cannot be orphaned), after a failed
  initialization, and when called twice.

### 7. `getButton` was removed

The top-level `getButton` function was an internal input-mapping detail and
is no longer exported. In the unlikely case you used it, inline the mapping:

```dart
PointerButton getButton(int value) {
  switch (value) {
    case kPrimaryMouseButton:
      return PointerButton.primary;
    case kSecondaryMouseButton:
      return PointerButton.secondary;
    case kTertiaryButton:
      return PointerButton.tertiary;
    default:
      return PointerButton.none;
  }
}
```

### 8. Focus handling is built in now

1.0.0 fixes
[upstream #230](https://github.com/jnschulze/flutter-webview-windows/issues/230)
at the native level: the WebView2 browser windows are reparented into the
Flutter view's window tree, so clicking a webview no longer deactivates the
host window, and clicking any Flutter widget outside a webview automatically
returns keyboard focus to Flutter.

If your app shipped workarounds for the old behavior, delete them. Common
ones were:

* re-activating the window with `window_manager` (or `SetForegroundWindow`
  via FFI) after webview clicks,
* `FocusNode` hacks that forced Flutter text fields to re-grab focus,
* overlays that intercepted clicks to keep them away from the webview.

The new behavior is automatic and needs no setup. For programmatic control
there is also a small new API:

```dart
await controller.focus();               // give the page keyboard focus
await WebviewController.releaseFocus(); // hand keyboard focus back to Flutter

controller.onFocusChanged.listen((focused) { ... });
final focused = controller.hasNativeFocus;
```

`Tab` traversal is also fixed: tabbing past the page's last focusable element
returns focus to Flutter instead of cycling inside the page.

### 9. Native toolchain notes

These only matter for building, not for your Dart code:

* Building requires Visual Studio 2022 with the *Desktop development with
  C++* workload and CMake 3.20+ (current Visual Studio installations bundle
  a newer CMake).
* The plugin itself is compiled as C++23, but it no longer forces a C++
  language level onto your app. In 0.4.x the plugin propagated `cxx_std_20`
  to consuming targets; if your own native code in `windows/runner` happened
  to rely on that, set it explicitly in your runner's `CMakeLists.txt`:

  ```cmake
  target_compile_features(${BINARY_NAME} PRIVATE cxx_std_20)
  ```

* The WebView2 SDK (`1.0.3967.48`) and WIL (`1.0.260126.7`) are downloaded
  via NuGet at configure time with SHA-256 verification of the NuGet
  bootstrap. No action is needed; if your build machine blocks the download,
  install [nuget.exe](https://www.nuget.org/downloads) and add it to `PATH`.

---

If you run into a migration issue not covered here, please
[open an issue](https://github.com/omar-hanafy/webview_flutter_windows/issues).
