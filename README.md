# webview_flutter_windows

[![pub package](https://img.shields.io/pub/v/webview_flutter_windows.svg)](https://pub.dev/packages/webview_flutter_windows)
[![CI](https://github.com/omar-hanafy/webview_flutter_windows/actions/workflows/ci.yml/badge.svg)](https://github.com/omar-hanafy/webview_flutter_windows/actions/workflows/ci.yml)

A WebView for Flutter on Windows, powered by
[Microsoft Edge WebView2](https://learn.microsoft.com/en-us/microsoft-edge/webview2/).
The browser is rendered off-screen and composited into your widget tree as a
regular Flutter `Texture`, so it behaves like any other widget: no airspace
issues, and transforms, opacity, and widgets painted on top all just work.

> **Fork notice:** this is a maintained fork of
> [jnschulze/flutter-webview-windows](https://github.com/jnschulze/flutter-webview-windows).
> It is not affiliated with the Flutter team's `webview_flutter` packages and
> keeps the controller/widget API from `webview_windows`.
> On top of upstream `0.4.0` it fixes the
> [window focus loss issue (#230)](https://github.com/jnschulze/flutter-webview-windows/issues/230),
> hardens the native COM and channel layers, modernizes the toolchain
> (WebView2 SDK `1.0.3967.48`, WIL `1.0.260126.7`, C++23), and ships a real
> test suite. Coming from upstream? Read the
> [migration guide](https://github.com/omar-hanafy/webview_flutter_windows/blob/main/migration_guide.md).

![Example app](https://user-images.githubusercontent.com/720469/116823636-d8b9fe00-ab85-11eb-9f91-b7bc819615ed.png)

## Features

- **Seamless composition.** Web content renders into a Flutter `Texture`
  inside your widget tree, not a native window floating above it.
- **Keyboard focus that works.** Clicking the webview does not deactivate
  your window, clicking back on Flutter UI restores Flutter's keyboard
  handling instantly, and `Tab` traversal leaves the page cleanly.
- **Typed broadcast event streams** for URL, loading state, document title,
  navigation history, security state, full-screen elements, downloads, load
  errors, web messages, and native focus.
- **Two-way JavaScript bridge**: execute scripts, register
  on-document-created scripts, and exchange JSON messages with the page.
- **Browser control**: full cookie management (read, write, delete), cache,
  user agent, zoom, background color, popup policy, virtual host mapping,
  suspend/resume, FPS limiting, and DevTools.
- **Headless mode**: drive a controller without a widget for background
  pages, scraping, or pre-warming.
- **Faithful input forwarding**: mouse, high-precision trackpad scrolling,
  and multi-touch.
- **High-DPI aware**, including per-view scale factors in multi-window apps.

## Requirements

**On your users' machines**

- Windows 10 1809 or newer (the off-screen compositor relies on
  `Windows.Graphics.Capture`).
- The [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/).
  It ships with Windows 11 and current Windows 10. To verify at startup, call
  `WebviewController.getWebViewVersion()`: if it returns `null`, guide the
  user to install the runtime.

**On your development machine**

- Flutter 3.44+ / Dart 3.12+
- Visual Studio 2022 with the *Desktop development with C++* workload
- A Windows 10/11 SDK (installed with the workload by default)
- Optional: `nuget.exe` in your `PATH` (the build downloads it automatically
  if missing)

## Installation

```sh
flutter pub add webview_flutter_windows
```

To track unreleased changes, depend on the repository instead:

```yaml
dependencies:
  webview_flutter_windows:
    git:
      url: https://github.com/omar-hanafy/webview_flutter_windows.git
      ref: main
```

## Quick start

Create a `WebviewController`, initialize it, and hand it to a `Webview`
widget:

```dart
import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

class BrowserPane extends StatefulWidget {
  const BrowserPane({super.key});

  @override
  State<BrowserPane> createState() => _BrowserPaneState();
}

class _BrowserPaneState extends State<BrowserPane> {
  final _controller = WebviewController();

  @override
  void initState() {
    super.initState();
    _initWebview();
  }

  Future<void> _initWebview() async {
    await _controller.initialize();
    await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
    await _controller.loadUrl('https://flutter.dev');
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? Webview(_controller)
        : const Center(child: CircularProgressIndicator());
  }
}
```

`initialize()` completes with an error if the WebView2 Runtime is missing
(error code `environment_creation_failed`), so wrap it in a `try`/`catch` if
you want to show a friendly install prompt.

## Listening to events

All controller streams are broadcast streams: attach as many listeners as you
like, but subscribe *before* triggering navigation, because events emitted
while nobody listens are dropped.

```dart
controller.url.listen((url) => debugPrint('URL: $url'));
controller.loadingState.listen((state) => debugPrint('State: $state'));
controller.title.listen((title) => debugPrint('Title: $title'));
controller.historyChanged.listen((h) => debugPrint('canGoBack: ${h.canGoBack}'));
controller.onLoadError.listen((status) => debugPrint('Load error: $status'));
controller.onDownloadEvent.listen((e) => debugPrint('${e.kind}: ${e.url}'));
```

## Talking to the page

Execute JavaScript and get its (JSON-decoded) result, or inject scripts that
run before any page script:

```dart
final title = await controller.executeScript('document.title');

final scriptId = await controller.addScriptToExecuteOnDocumentCreated(
  'window.myAppReady = true;',
);
```

Exchange structured messages with the page:

```dart
// Dart -> page
await controller.postWebMessage('{"command": "ping"}');

// page -> Dart
controller.webMessage.listen((message) {
  debugPrint('Page says: $message'); // already JSON-decoded
});
```

And on the JavaScript side:

```js
window.chrome.webview.addEventListener('message', (e) => {
  console.log(e.data); // {command: 'ping'}
});
window.chrome.webview.postMessage({command: 'pong'});
```

## Cookies

Read, write, and delete cookies through the WebView2 cookie store - useful
for extracting a session token after a login flow or seeding one before it:

```dart
final cookies = await controller.getCookies('https://example.com');
final session = cookies.firstWhere((c) => c.name == 'session');

await controller.setCookie(WebviewCookie(
  name: 'theme',
  value: 'dark',
  domain: '.example.com',
  expires: DateTime.now().add(const Duration(days: 30)),
  isSecure: true,
  sameSite: WebviewCookieSameSite.strict,
));

await controller.deleteCookies('theme', uri: 'https://example.com');
await controller.clearCookies(); // everything
```

Omit `expires` to create a session cookie; pass an empty `uri` to
`getCookies` to list every cookie of the profile.

## Headless usage

A controller works without a `Webview` widget: initialize it, give the
invisible page real bounds with `setSize` (pages do not perform layout until
they have nonzero bounds), and drive it through the normal API - load pages,
run scripts, exchange messages, read cookies. Nothing is rendered and no
frames are captured:

```dart
final background = WebviewController();
await background.initialize();
await background.setSize(const Size(1280, 720));
await background.loadUrl('https://example.com/login');
// ... executeScript, webMessage, getCookies ...
await background.dispose();
```

## Permission requests

Web content can request browser permissions (camera, microphone, geolocation,
clipboard, notifications). Decide per request via the `Webview` widget:

```dart
Webview(
  controller,
  permissionRequested: (url, kind, isUserInitiated) async {
    final allowed = await askTheUser(url, kind);
    return allowed
        ? WebviewPermissionDecision.allow
        : WebviewPermissionDecision.deny;
  },
)
```

Return `WebviewPermissionDecision.none` to defer to the WebView2 default.

## Keyboard focus

Clicking into the webview gives the page real Win32 keyboard focus; clicking
any Flutter widget hands focus back automatically. On top of that, one
invariant is enforced in both directions: **while a Flutter text input owns
Flutter focus, no webview keeps native keyboard focus.** If a dialog's
`TextField` gains focus while the page has the keyboard, focus is handed
back; if anything - `focus()`, page script, a stale refocus path in app
code - grabs native focus while a text input is focused, the grab is
reverted immediately. Typing can never silently land in the page. To move
focus into the page programmatically, unfocus the text input first. You
normally do not have to manage any of this. For programmatic control:

```dart
await controller.focus();               // move keyboard focus into the page
await WebviewController.releaseFocus(); // hand it back to Flutter

controller.onFocusChanged.listen((focused) => debugPrint('Page focus: $focused'));
final focused = controller.hasNativeFocus;
```

## Configuring the browser environment

The WebView2 environment is shared by all controllers and is created lazily
on the first `initialize()`. To customize it (user data directory, browser
executable, Chromium command line flags), configure it once *before* creating
any controller:

```dart
await WebviewController.initializeEnvironment(
  userDataPath: r'C:\path\to\profile',
  additionalArguments: '--show-fps-counter',
);
```

The environment's lifecycle is reference counted: it is released when the
last controller is disposed. That means `initializeEnvironment` can be
called again - for example with a different `userDataPath` - once all
controllers are gone; it only throws a `PlatformException` while controllers
are alive.

## Example app and tests

A complete example (URL bar, loading indicator, DevTools, permission prompts)
lives in [`example/`](example/): `cd example && flutter run -d windows`.

The repository also ships:

- a Dart test suite (`flutter test`) covering the channel contract of every
  controller method, the controller lifecycle, all events, and input/focus
  forwarding,
- native C++ unit tests (GoogleTest), run from the repository root:

  ```sh
  cmake -S windows/test -B build/native_tests
  cmake --build build/native_tests --config Release
  ctest --test-dir build/native_tests -C Release --output-on-failure
  ```

- a real-input integration test for the focus behavior
  (`example/integration_test/focus_test.dart`), which needs an interactive
  Windows session.

Tip for your own widget tests: when driving a `WebviewController` under
`testWidgets`, wrap `initialize()` and `dispose()` in `tester.runAsync(...)`.
Test bodies run in a fake-async zone where platform channel futures are not
driven, so awaiting them directly hangs the test.

## Limitations

WebView2 has no official off-screen rendering API yet
([WebView2Feedback#20](https://github.com/MicrosoftEdge/WebView2Feedback/issues/20),
[#526](https://github.com/MicrosoftEdge/WebView2Feedback/issues/526),
[#547](https://github.com/MicrosoftEdge/WebView2Feedback/issues/547)).
This plugin obtains frames through `Windows.Graphics.Capture`, which is why
Windows versions older than Windows 10 1809 are not supported.

## Troubleshooting

- **`initialize()` fails with `environment_creation_failed`**: the WebView2
  Runtime is missing. Check `WebviewController.getWebViewVersion()` and point
  the user to the [runtime installer](https://developer.microsoft.com/en-us/microsoft-edge/webview2/).
- **The build cannot download NuGet**: install
  [nuget.exe](https://www.nuget.org/downloads) manually and add it to `PATH`.
- **Keyboard input stays in the page after clicking it**: that is by design;
  click any Flutter widget or call `WebviewController.releaseFocus()` to
  return focus to Flutter.

## Migrating from upstream 0.4.x

Version 1.0.0 contains breaking changes (SDK floors, broadcast streams,
`WebErrorStatus` renames, stricter lifecycle errors). The
[migration guide](https://github.com/omar-hanafy/webview_flutter_windows/blob/main/migration_guide.md)
walks through every one of them, including the focus workarounds you can now
delete.

## Credits and license

Created by [Niklas Schulze (jnschulze)](https://github.com/jnschulze); this
fork is maintained by [Omar Hanafy](https://github.com/omar-hanafy).
Licensed under the [BSD 3-Clause License](LICENSE).
