---
name: integrate-webview-windows
description: Use when adding or embedding a WebView2 browser view in a Flutter Windows desktop app with the webview_flutter_windows package - creating or wiring a WebviewController or Webview widget, configuring popups, context menus, permission requests, background color, zoom, or user agent, running a headless controller without a widget, customizing the browser environment (user data folder, Chromium flags), or detecting a missing WebView2 Runtime at startup.
---

# Integrate webview_flutter_windows

Embed WebView2-rendered web content as a regular Flutter `Texture` on Windows.
This skill is the ground truth for the package API. `webview_flutter_windows`
was first published in 2026; if your training data does not include it, trust
this skill and `references/api-quick-reference.md` over memory, and never
substitute APIs from `webview_flutter` or the older `webview_windows`.

## Scope check

- Android, iOS, macOS, Linux, or web webviews: this package is Windows-only.
  Use the `webview_flutter` family instead; stop here.
- Project currently uses the upstream `webview_windows` package: use the
  `migrate-from-webview-windows` skill first.
- An existing integration is broken (blank view, focus issues, build errors):
  use the `troubleshoot-webview-windows` skill.
- JavaScript execution, Dart/page messaging, or serving local HTML/assets:
  use the `bridge-webview-windows` skill.

## Inspect the project first

1. `pubspec.yaml`: is `webview_flutter_windows` already a dependency? Which
   version? `setDefaultContextMenusEnabled` needs `>=1.1.0`.
2. SDK floors: the package requires `sdk: ^3.12.0` and `flutter: >=3.44.0`.
   If the project's floors are lower, raise them (or flag the conflict) before
   adding the dependency.
3. Does `windows/` exist? If not, this is not a Windows-enabled Flutter app;
   run `flutter create --platforms=windows .` only with the user's consent.
4. Look for existing `WebviewController` usage and the project's state
   management pattern; extend it, do not impose a new one.

Add the dependency with `flutter pub add webview_flutter_windows` (or edit
`pubspec.yaml` and run `flutter pub get`). Never depend on both
`webview_windows` and `webview_flutter_windows`: they register the same
native plugin class and method channel and conflict at runtime.

## Canonical lifecycle

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

class BrowserPane extends StatefulWidget {
  const BrowserPane({super.key});

  @override
  State<BrowserPane> createState() => _BrowserPaneState();
}

class _BrowserPaneState extends State<BrowserPane> {
  final _controller = WebviewController();
  String? _initError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();

      // 1. Configure before navigating.
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      // 2. Subscribe before navigating (streams drop unheard events).
      _controller.url.listen((url) => debugPrint('url: $url'));
      _controller.onLoadError.listen((status) => debugPrint('error: $status'));

      // 3. Navigate last.
      await _controller.loadUrl('https://example.com');

      if (mounted) setState(() {});
    } on PlatformException catch (e) {
      // 'environment_creation_failed' usually means the WebView2 Runtime is
      // missing; see "Detect the WebView2 Runtime" below.
      if (mounted) setState(() => _initError = '${e.code}: ${e.message}');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) return Center(child: Text(_initError!));
    return _controller.value.isInitialized
        ? Webview(_controller)
        : const Center(child: CircularProgressIndicator());
  }
}
```

Lifecycle rules the code above encodes:

- `initialize()` must complete before any other controller method; calling
  early throws `StateError`. It is re-entrant: concurrent calls join the
  in-flight attempt, calling again after success is a no-op, and a failed
  attempt may be retried.
- Gate the `Webview` widget on `controller.value.isInitialized`.
- `dispose()` is idempotent and safe in every state; after it, controller
  methods are silent no-ops. Always dispose in `State.dispose`.
- `controller.ready` completes on success and also when the controller is
  disposed before initializing; check `value.isInitialized` after awaiting.

## The three ordering rules

1. **Subscribe before navigating.** Every stream is a broadcast stream:
   multiple listeners are fine, but events emitted while nobody listens are
   dropped, and there is no replay for late subscribers.
2. **Configure before the navigation that needs it.** `setUserAgent`,
   `setPopupWindowPolicy`, and `setDefaultContextMenusEnabled` affect
   behavior from the next top-level navigation onward.
3. **`initializeEnvironment` before any controller exists.** The WebView2
   environment (user data folder, browser executable, Chromium flags) is
   shared by all controllers and created lazily on first `initialize()`.
   `WebviewController.initializeEnvironment(...)` throws `PlatformException`
   while any controller is alive. The environment is reference counted and
   released when the last controller is disposed, after which it may be
   configured again.

## Configuration decision points

| Concern | API | Notes |
| --- | --- | --- |
| Popups | `setPopupWindowPolicy(allow / deny / sameWindow)` | WebView2 default opens new windows; kiosks usually want `deny` or `sameWindow`. |
| Right-click menus | `setDefaultContextMenusEnabled(bool)` | **Disabled by default by this package.** Opt in after `initialize()` and before the relevant navigation. Requires package `>=1.1.0`. |
| Permission prompts | `Webview(controller, permissionRequested: ...)` | Delegate receives url, `WebviewPermissionKind`, isUserInitiated; return `allow`, `deny`, or `none` (defer to WebView2 default). Without a delegate the WebView2 default applies. |
| Background | `setBackgroundColor(color)` | Fully transparent works; semi-transparent does not (any nonzero alpha renders opaque). |
| Scaling | `Webview(scaleFactor: ...)`, `filterQuality` | Defaults to the view's device pixel ratio (multi-window safe); leave defaults unless mimicking pre-high-DPI behavior. |
| Resource use | `setFpsLimit(n)`, `suspend()` / `resume()` | Suspend hidden webviews; 0 or null removes the FPS cap. |

## Detect the WebView2 Runtime

The Evergreen WebView2 Runtime ships with Windows 11 and current Windows 10,
but can be absent on older or locked-down machines. Two detection layers:

```dart
final version = await WebviewController.getWebViewVersion();
if (version == null) {
  // Runtime missing: show install guidance pointing to
  // https://developer.microsoft.com/en-us/microsoft-edge/webview2/
}
```

Additionally, `initialize()` completes with a `PlatformException`
(code `environment_creation_failed`) when the environment cannot be created.
Handle both; do not assume the runtime exists in production apps. Minimum OS:
Windows 10 1809 (the compositor uses `Windows.Graphics.Capture`).

## Headless controllers (no widget)

A controller works without a `Webview` widget for background pages, scraping,
or pre-warming: initialize it, then give the page real bounds, because pages
do not perform layout until they have nonzero bounds:

```dart
final background = WebviewController();
await background.initialize();
await background.setSize(const Size(1280, 720));
await background.loadUrl('https://example.com');
// executeScript, webMessage, getCookies ... then:
await background.dispose();
```

Nothing is rendered and no frames are captured. `Webview` widgets call
`setSize` automatically; call it manually only in headless use.

## Keyboard focus

Focus handoff is automatic: clicking the page gives it real Win32 keyboard
focus; clicking any Flutter widget hands focus back. One invariant is
enforced in both directions: while a Flutter text input owns Flutter focus,
no webview keeps native keyboard focus (grabs are reverted immediately). Do
not add focus workarounds. For programmatic control: `controller.focus()`
(unfocus the Flutter text input first, or the grab is reverted),
`WebviewController.releaseFocus()`, `onFocusChanged`, `hasNativeFocus`.

## Verify

1. `dart format` the changed files, then run `flutter analyze` (or
   `dart analyze`) and fix everything it reports.
2. Run the project's tests. For widget tests around this package, use the
   `test-webview-windows` skill (channels must be mocked; `initialize` and
   `dispose` need `tester.runAsync`).
3. On a Windows machine: `flutter run -d windows`, then manually check: page
   loads, clicking into the page and typing works, clicking a Flutter text
   field returns typing to Flutter, popup and context menu behavior matches
   the chosen configuration. On non-Windows hosts, state explicitly that
   runtime verification still needs a Windows run.

## Failure handling

| Symptom | Meaning | Action |
| --- | --- | --- |
| `PlatformException(environment_creation_failed)` | Runtime missing or user-data-folder problem | Runtime detection UX above; `troubleshoot-webview-windows` skill |
| `PlatformException(webview_creation_failed)` | Environment exists, controller creation failed | `troubleshoot-webview-windows` skill |
| `StateError: ... not initialized` | Method called before `initialize()` completed | Fix call order; gate UI on `value.isInitialized` |
| `MissingPluginException` | Running on a non-Windows host or in a test without mocks | Guard with `Platform.isWindows`; in tests use `test-webview-windows` |
| Widget shows nothing | Controller not initialized, or headless without `setSize` | Gate on `isInitialized`; call `setSize` in headless use |

## Example scenario

"Add a browser pane with an address bar that follows navigation and let users
right-click images to copy them": inspect pubspec (needs `>=1.1.0`), build
the canonical lifecycle above, add
`await controller.setDefaultContextMenusEnabled(true)` after `initialize()`
and before `loadUrl`, bind a `TextField` to `controller.url` events and call
`controller.loadUrl` on submit, then run the verification steps.

For the full API surface (all methods, streams, enums, widget parameters,
cookie model), read `references/api-quick-reference.md` in this skill
directory.
