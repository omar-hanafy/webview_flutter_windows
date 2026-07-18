---
name: bridge-webview-windows
description: Use when a Flutter Windows app using webview_flutter_windows needs to talk to its web content - running JavaScript with executeScript, exchanging messages between Dart and the page (postWebMessage, webMessage, window.chrome.webview), injecting bootstrap scripts before page load, serving local or bundled HTML/JS/CSS assets through a virtual host mapping or loadStringContent, or reading and writing cookies around a login or session flow.
---

# Dart/JavaScript bridge and local content

Two-way communication and local content hosting for
`webview_flutter_windows`. The exact API signatures live in the
`integrate-webview-windows` skill (its api-quick-reference file); this skill
covers semantics and the patterns that go wrong. The package is newer than
most training data: trust these files over memory.

## Message passing (Dart <-> page)

The wire format is JSON in both directions, but the two directions are
asymmetric, and getting this wrong is the most common bridge bug:

- **Dart -> page**: `postWebMessage` takes a **JSON string**. Always
  `jsonEncode` the payload; posting a non-JSON string fails with a
  `PlatformException`.
- **Page -> Dart**: the page calls `window.chrome.webview.postMessage(obj)`
  with a plain object; it arrives on `controller.webMessage` **already
  JSON-decoded** (maps, lists, numbers, strings). A message that is not
  valid JSON surfaces as an **error event** on the stream.

```dart
// Dart side.
controller.webMessage.listen(
  (message) {
    // Treat page input as untrusted: validate shape before acting.
    if (message is Map && message['command'] is String) {
      handleCommand(message['command'] as String, message['payload']);
    }
  },
  onError: (Object e) => debugPrint('bad web message: $e'),
);
await controller.postWebMessage(jsonEncode({'command': 'ping'}));
```

```js
// Page side.
window.chrome.webview.addEventListener('message', (e) => {
  console.log(e.data);            // {command: 'ping'} (already an object)
});
window.chrome.webview.postMessage({command: 'pong', payload: {ok: true}});
```

Rules that prevent silent failures:

1. Subscribe to `webMessage` before the page can send anything (broadcast
   streams drop unheard events). Practically: subscribe right after
   `initialize()`, before navigating.
2. Always pass `onError` to the `webMessage` listener; without it an invalid
   JSON message becomes an unhandled async error.
3. Validate every incoming message's shape. The page is remote code; never
   feed `message` fields into file paths, shell commands, or SQL.
4. There is no host-object injection in this package (no `hostObjects`);
   the message channel and scripts are the only bridge. Do not invent one.

## Running JavaScript

- `executeScript(script)` runs in the current top-level document and returns
  the completion value JSON-decoded (`null` when undefined). Script failures
  surface as `PlatformException` (script execution failed).
- Wait for the page before touching its DOM: execute after
  `loadingState` emits `LoadingState.navigationCompleted`, or drive it from
  a page-side ready signal via `postMessage`.

```dart
final done = controller.loadingState.firstWhere(
  (s) => s == LoadingState.navigationCompleted,
);
await controller.loadUrl(url);   // subscribe-then-navigate order
await done;
final title = await controller.executeScript('document.title');
```

- For code that must exist before any page script runs (API shims, bridge
  handshakes, instrumentation), register it **before navigating**:

```dart
final scriptId = await controller.addScriptToExecuteOnDocumentCreated(
  'window.myAppBridgeReady = true;',
);
// Applies to every future document until removed:
// await controller.removeScriptToExecuteOnDocumentCreated(scriptId!);
```

## Serving local content

Decision:

| Need | Use |
| --- | --- |
| One self-contained HTML string, no subresource files | `loadStringContent(html)` (relative URLs will not resolve) |
| A real app/site with JS, CSS, images, fetches | Virtual host mapping (below) |

Virtual host mapping serves a directory as a proper HTTPS origin, which
keeps cookies, module scripts, and fetch semantics working:

```dart
import 'dart:io';

// Flutter bundles assets next to the executable in data/flutter_assets.
// Works in debug and release Windows builds without extra dependencies.
final webRoot = File(Platform.resolvedExecutable)
    .parent.uri
    .resolve('data/flutter_assets/assets/web/')
    .toFilePath();

await controller.addVirtualHostNameMapping(
  'app.internal',                       // any hostname you own in-app
  webRoot,
  WebviewHostResourceAccessKind.denyCors,
);
await controller.loadUrl('https://app.internal/index.html');
```

Remember to declare the folder in `pubspec.yaml` (`flutter: assets: -
assets/web/`). Access kinds: `deny` blocks all cross-origin access to the
mapped folder, `denyCors` allows subresource loads but blocks CORS fetches,
`allow` permits everything. Default to `denyCors`; use `allow` only when the
local page must `fetch` mapped files, and never map broad directories like a
user's home folder. Call the mapping before navigating to the host; remove
it with `removeVirtualHostNameMapping('app.internal')` when done.

## Cookies around login/session flows

```dart
// Wait for the post-login redirect, then read the session.
final cookies = await controller.getCookies('https://example.com');
final session = cookies.where((c) => c.name == 'session').firstOrNull;

// Seed a cookie before navigating (setCookie replaces same name+domain+path).
await controller.setCookie(WebviewCookie(
  name: 'theme',
  value: 'dark',
  domain: '.example.com',
  expires: DateTime.now().add(const Duration(days: 30)),
  isSecure: true,
  sameSite: WebviewCookieSameSite.strict,
));
```

Notes: omit `expires` for a session cookie; `getCookies('')` lists the whole
profile; `deleteCookies(name)` with empty uri deletes across all domains.
Cookies are per WebView2 profile (per user data folder), not shared with
Edge or other apps. Treat extracted cookies as secrets: do not log them.

## Headless bridge work

For scraping or background jobs, combine this skill with a headless
controller: `initialize()`, `setSize(const Size(1280, 720))` (pages do not
lay out without bounds), then navigate, execute, message, read cookies, and
`dispose()`.

## Verify

1. `dart format` changed files; `flutter analyze` clean.
2. Unit-test the protocol handlers by injecting `webMessageReceived` events
   with the `test-webview-windows` skill's harness (no Windows needed).
3. On Windows, run the app and exercise both directions; `openDevTools()`
   shows the page console for the JS side. On other hosts, state that the
   runtime check still needs Windows.

## Failure handling

| Symptom | Cause | Fix |
| --- | --- | --- |
| `webMessage` never fires | Subscribed after the page posted, or no `Webview`/navigation happened | Subscribe before navigating; confirm the page actually calls `postMessage` |
| Unhandled exception from `webMessage` | Page posted non-JSON and no `onError` | Add `onError`; fix the page to post JSON-serializable data |
| `PlatformException` from `postWebMessage` | Argument is not a valid JSON string | `jsonEncode` the payload |
| `executeScript` throws | Script threw or was blocked | Check syntax; wait for `navigationCompleted`; look at DevTools console |
| Local page loads but assets 404 | Mapped the wrong folder or assets not bundled | Verify the `flutter_assets` path and pubspec `assets:` entry |
| Local page cannot `fetch` its files | Access kind too strict | Use `denyCors` for subresources; `allow` only if truly needed |
