---
name: add-controller-method
description: Use when adding, renaming, or extending a WebviewController method, stream, or enum in this repository - any change that touches the Dart/method-channel/native contract of webview_flutter_windows.
---

# Add a controller method end to end

A controller capability spans four files that must change together in one
PR: `lib/src/webview.dart`, `test/webview_flutter_windows_test.dart`,
`windows/webview_bridge.cc`, and `windows/webview.h` + `windows/webview.cc`.
The reference implementation of this whole flow is
`setDefaultContextMenusEnabled` (PR #3); mirror its shape.

## 1. Dart method (`lib/src/webview.dart`)

```dart
/// One-line summary ending with a period.
///
/// Behavior, ordering constraints (e.g. "applies to the next top-level
/// navigation"), and failure modes. Link the WebView2 reference when the
/// method wraps a WebView2 API.
Future<void> setDefaultContextMenusEnabled(bool enabled) async {
  if (_isDisposed) {
    return;
  }
  return _channel.invokeMethod('setDefaultContextMenusEnabled', enabled);
}
```

Rules: `_isDisposed` guard first (disposed controllers are silent no-ops,
returning `null`/empty for value-returning methods); use `_channel` (throws
the standard `StateError` before initialize); dartdoc is mandatory
(`public_member_api_docs` is an analyzer error); wire name in lowerCamelCase
shared verbatim with the bridge.

## 2. Dart tests (same PR, `test/webview_flutter_windows_test.dart`)

In the `methods` group: assert the exact wire contract (method name and
argument shape), e.g. both enabled states. If the native side can fail, add
an error-propagation test (`onInstanceCall` throwing a `PlatformException`)
like `setDefaultContextMenusEnabled propagates native failures`. Also add
the method to the `uninitialized controller` StateError expectations when
the pattern applies.

## 3. Bridge (`windows/webview_bridge.cc`)

Add the constant near its peers:

```cpp
constexpr auto kMethodSetDefaultContextMenusEnabled =
    "setDefaultContextMenusEnabled";
```

Add the `HandleMethodCall` branch. Validate arguments with `std::get_if`
and return structured errors; never crash on malformed input:

```cpp
// setDefaultContextMenusEnabled: bool
if (method_name.compare(kMethodSetDefaultContextMenusEnabled) == 0) {
  if (const auto enabled = std::get_if<bool>(method_call.arguments())) {
    if (webview_->SetDefaultContextMenusEnabled(*enabled)) {
      return result->Success();
    }
    return result->Error(kMethodFailed,
                         "Updating the default context menu setting failed.");
  }
  return result->Error(kErrorInvalidArgs);
}
```

## 4. Native (`windows/webview.h`, `windows/webview.cc`)

Declare `bool SetDefaultContextMenusEnabled(bool enabled);` with the other
setters; implement with explicit HRESULT handling and null checks on COM
pointers:

```cpp
bool Webview::SetDefaultContextMenusEnabled(bool enabled) {
  if (!settings_) {
    return false;
  }
  return SUCCEEDED(
      settings_->put_AreDefaultContextMenusEnabled(enabled ? TRUE : FALSE));
}
```

Follow the existing RAII/wil conventions; register event tokens in
`event_registrations_` and revoke them in the destructor when adding events.

## 5. Enums and events

- Enum values cross the channel as indexes: append only, never reorder, and
  extend the matching `native enum contracts` test. Keep the `// Order must
  match ...` comment pointing at the native definition.
- New native -> Dart events: emit `{'type': ..., 'value': ...}` from the
  bridge, handle the type in `_handleEvent`, back it with a broadcast
  `StreamController` that `dispose()` closes, and test the delivery.

## 6. Docs and scope

Update the README section and `example/` only when users need new guidance.
Do NOT touch `pubspec.yaml` version or `CHANGELOG.md`; releases do that
(see the `prepare-release` skill). If the capability is user-facing, the
consumer skill files under
`agent_plugins/webview-flutter-windows/skills/` likely need the new API in
their reference tables; update them and run
`dart tool/validate_agent_plugin.dart`.

## 7. Validate

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

On Windows also: native tests (`cmake -S windows/test -B build/native_tests
&& cmake --build build/native_tests --config Release && ctest --test-dir
build/native_tests -C Release --output-on-failure`) and
`cd example && flutter build windows --release`. On non-Windows hosts,
state that the native gates run in CI; do not claim them.
