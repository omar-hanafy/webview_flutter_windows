# webview_flutter_windows API quick reference

Package: `webview_flutter_windows` (pub.dev). Import:

```dart
import 'package:webview_flutter_windows/webview_flutter_windows.dart';
```

Windows-only Flutter plugin. Requires Dart `^3.12.0`, Flutter `>=3.44.0`,
Windows 10 1809+ at runtime, and the WebView2 Runtime on the user's machine.
This file mirrors the 1.1.x public API exactly; prefer it over model memory.

## WebviewController statics

| Member | Signature | Notes |
| --- | --- | --- |
| `initializeEnvironment` | `static Future<void> initializeEnvironment({String? userDataPath, String? browserExePath, String? additionalArguments})` | Configure the shared WebView2 environment. Call before any controller is initialized; throws `PlatformException` while controllers are alive. Reference counted: reconfigurable after the last controller is disposed. |
| `getWebViewVersion` | `static Future<String?> getWebViewVersion()` | Browser version, or `null` when the WebView2 Runtime is not installed. |
| `releaseFocus` | `static Future<void> releaseFocus()` | Returns Win32 keyboard focus to Flutter. Safe anywhere; swallows errors on non-Windows hosts. |

## WebviewController lifecycle

| Member | Signature | Notes |
| --- | --- | --- |
| constructor | `WebviewController()` | Uninitialized; extends `ValueNotifier<WebviewValue>`. |
| `initialize` | `Future<void> initialize()` | Re-entrant; joins in-flight attempt; retry allowed after failure; `StateError` after dispose. Failure completes the future with the error (often `PlatformException`). |
| `ready` | `Future<void> get ready` | Completes on init success or on dispose-before-init; never hangs. Check `value.isInitialized` afterwards. |
| `value` | `WebviewValue` | `value.isInitialized` gates everything. |
| `dispose` | `Future<void> dispose()` | Idempotent, safe in every state, closes all streams (`done`). After dispose, methods are silent no-ops (returning `null`/empty where applicable). |

Calling any instance method before `initialize()` completes throws
`StateError('WebviewController is not initialized. Call initialize() first.')`.

## Navigation and content

| Method | Signature |
| --- | --- |
| `loadUrl` | `Future<void> loadUrl(String url)` |
| `loadStringContent` | `Future<void> loadStringContent(String content)` |
| `reload` / `stop` | `Future<void> reload()`, `Future<void> stop()` |
| `goBack` / `goForward` | `Future<void> goBack()`, `Future<void> goForward()` |
| `addVirtualHostNameMapping` | `Future<void> addVirtualHostNameMapping(String hostName, String folderPath, WebviewHostResourceAccessKind accessKind)` |
| `removeVirtualHostNameMapping` | `Future<void> removeVirtualHostNameMapping(String hostName)` |

## Scripts and messaging

| Method | Signature | Notes |
| --- | --- | --- |
| `executeScript` | `Future<dynamic> executeScript(String script)` | Returns the JSON-decoded result, or `null`. |
| `addScriptToExecuteOnDocumentCreated` | `Future<ScriptID?> addScriptToExecuteOnDocumentCreated(String script)` | Runs before any page script on every future document. `ScriptID` is a `String`. |
| `removeScriptToExecuteOnDocumentCreated` | `Future<void> removeScriptToExecuteOnDocumentCreated(ScriptID scriptId)` | |
| `postWebMessage` | `Future<void> postWebMessage(String message)` | Argument must be a JSON string (`jsonEncode(...)`). |

## Cookies

| Method | Signature | Notes |
| --- | --- | --- |
| `getCookies` | `Future<List<WebviewCookie>> getCookies([String uri = ''])` | Empty uri: every cookie of the profile. |
| `setCookie` | `Future<void> setCookie(WebviewCookie cookie)` | Replaces same name+domain+path. |
| `deleteCookies` | `Future<void> deleteCookies(String name, {String uri = ''})` | Empty uri: every domain and path. |
| `clearCookies` / `clearCache` | `Future<void>` | Whole profile. |
| `setCacheDisabled` | `Future<void> setCacheDisabled(bool disabled)` | |

`WebviewCookie` fields: `name`, `value`, `domain` (default `''`), `path`
(default `'/'`), `expires` (`DateTime?`, `null` = session cookie, see
`isSession`), `isSecure` (false), `isHttpOnly` (false), `sameSite`
(`WebviewCookieSameSite.lax`).

## Settings and control

| Method | Signature | Notes |
| --- | --- | --- |
| `setUserAgent` | `Future<void> setUserAgent(String userAgent)` | |
| `setBackgroundColor` | `Future<void> setBackgroundColor(Color color)` | Semi-transparency unsupported: nonzero alpha renders opaque. |
| `setZoomFactor` | `Future<void> setZoomFactor(double zoomFactor)` | |
| `setPopupWindowPolicy` | `Future<void> setPopupWindowPolicy(WebviewPopupWindowPolicy policy)` | |
| `setDefaultContextMenusEnabled` | `Future<void> setDefaultContextMenusEnabled(bool enabled)` | Menus are disabled by default by this package. Applies from the next top-level navigation. Package `>=1.1.0`. |
| `suspend` / `resume` | `Future<void>` | Reduce resource usage while hidden. |
| `openDevTools` | `Future<void> openDevTools()` | Separate window. |
| `setFpsLimit` | `Future<void> setFpsLimit([int? maxFps = 0])` | 0 or null removes the limit. |
| `setSize` | `Future<void> setSize(Size size, {double scaleFactor = 1.0, Offset offset = Offset.zero})` | Headless only; `Webview` widgets call it automatically whenever their size, position or scale changes. `offset` (package `>=1.2.0`) is the surface's top-left corner relative to the window's client origin; custom `Texture` embeddings must pass it or WebView2 displaces dropdowns, autofill bubbles and context menus by exactly the inset. |
| `focus` | `Future<void> focus()` | Grab is reverted while a Flutter text input owns primary focus. |

## Streams (all broadcast; unheard events are dropped; `done` on dispose)

| Stream | Type | Emits |
| --- | --- | --- |
| `url` | `Stream<String>` | Current URL changes. |
| `loadingState` | `Stream<LoadingState>` | `none`, `loading`, `navigationCompleted`. |
| `onLoadError` | `Stream<WebErrorStatus>` | Failed navigations. Unknown future statuses map to `WebErrorStatus.unknown`. |
| `title` | `Stream<String>` | Document title. |
| `historyChanged` | `Stream<HistoryChanged>` | `canGoBack` / `canGoForward` booleans. |
| `securityStateChanged` | `Stream<String>` | JSON string (Chrome DevTools Protocol payload). |
| `webMessage` | `Stream<dynamic>` | JSON-decoded page messages; error event on invalid JSON. |
| `onDownloadEvent` | `Stream<WebviewDownloadEvent>` | `kind`, `url`, `resultFilePath`, `bytesReceived`, `totalBytesToReceive`. |
| `containsFullScreenElementChanged` | `Stream<bool>` | Full-screen element presence. |
| `onFocusChanged` | `Stream<bool>` | Native (Win32) keyboard focus; also `bool get hasNativeFocus`. |

## Webview widget

```dart
const Webview(
  WebviewController controller, {
  Key? key,
  double? width,               // both width and height, or the widget expands
  double? height,
  PermissionRequestedDelegate? permissionRequested,
  double? scaleFactor,         // default: the view's devicePixelRatio
  FilterQuality filterQuality = FilterQuality.none,
})
```

`PermissionRequestedDelegate`:
`FutureOr<WebviewPermissionDecision> Function(String url, WebviewPermissionKind kind, bool isUserInitiated)`.

## Enums (order is part of the native wire contract; never reorder)

- `LoadingState`: `none`, `loading`, `navigationCompleted`
- `WebviewPermissionKind`: `unknown`, `microphone`, `camera`, `geoLocation`,
  `notifications`, `otherSensors`, `clipboardRead`
- `WebviewPermissionDecision`: `none`, `allow`, `deny`
- `WebviewPopupWindowPolicy`: `allow`, `deny`, `sameWindow`
- `WebviewHostResourceAccessKind`: `deny`, `allow`, `denyCors`
- `WebviewCookieSameSite`: `none`, `lax`, `strict`
- `WebviewDownloadEventKind`: `downloadStarted`, `downloadCompleted`,
  `downloadProgress`
- `WebErrorStatus` (lowerCamelCase): `unknown`,
  `certificateCommonNameIsIncorrect`, `certificateExpired`,
  `clientCertificateContainsErrors`, `certificateRevoked`,
  `certificateIsInvalid`, `serverUnreachable`, `timeout`,
  `errorHttpInvalidServerResponse`, `connectionAborted`, `connectionReset`,
  `disconnected`, `cannotConnect`, `hostNameNotResolved`,
  `operationCanceled`, `redirectFailed`, `unexpectedError`,
  `validAuthenticationCredentialsRequired`,
  `validProxyAuthenticationRequired`

## Support classes

- `WebviewValue`: `isInitialized` plus `copyWith`.
- `HistoryChanged`: `canGoBack`, `canGoForward`.
- `WebviewDownloadEvent`: `kind`, `url`, `resultFilePath`, `bytesReceived`,
  `totalBytesToReceive` (0 when unknown).

## Error codes (PlatformException.code from the native side)

`environment_creation_failed`, `webview_creation_failed`,
`invalid_arguments`, `invalid_id`, `unsupported_platform`, plus
method-specific failures such as script execution errors. See the
`troubleshoot-webview-windows` skill for the symptom-keyed catalog.
