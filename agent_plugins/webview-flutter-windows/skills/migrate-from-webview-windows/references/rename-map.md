# webview_windows 0.4.x -> webview_flutter_windows 1.x rename map

## Package and import

| 0.4.x | 1.x |
| --- | --- |
| `webview_windows: ^0.4.0` (pubspec) | `webview_flutter_windows: ^1.1.1` |
| `package:webview_windows/webview_windows.dart` | `package:webview_flutter_windows/webview_flutter_windows.dart` |

## WebErrorStatus values (complete, 19 rows)

Underlying wire indexes are unchanged.

| 0.4.x | 1.x |
| --- | --- |
| `WebErrorStatus.WebErrorStatusUnknown` | `WebErrorStatus.unknown` |
| `WebErrorStatus.WebErrorStatusCertificateCommonNameIsIncorrect` | `WebErrorStatus.certificateCommonNameIsIncorrect` |
| `WebErrorStatus.WebErrorStatusCertificateExpired` | `WebErrorStatus.certificateExpired` |
| `WebErrorStatus.WebErrorStatusClientCertificateContainsErrors` | `WebErrorStatus.clientCertificateContainsErrors` |
| `WebErrorStatus.WebErrorStatusCertificateRevoked` | `WebErrorStatus.certificateRevoked` |
| `WebErrorStatus.WebErrorStatusCertificateIsInvalid` | `WebErrorStatus.certificateIsInvalid` |
| `WebErrorStatus.WebErrorStatusServerUnreachable` | `WebErrorStatus.serverUnreachable` |
| `WebErrorStatus.WebErrorStatusTimeout` | `WebErrorStatus.timeout` |
| `WebErrorStatus.WebErrorStatusErrorHTTPInvalidServerResponse` | `WebErrorStatus.errorHttpInvalidServerResponse` |
| `WebErrorStatus.WebErrorStatusConnectionAborted` | `WebErrorStatus.connectionAborted` |
| `WebErrorStatus.WebErrorStatusConnectionReset` | `WebErrorStatus.connectionReset` |
| `WebErrorStatus.WebErrorStatusDisconnected` | `WebErrorStatus.disconnected` |
| `WebErrorStatus.WebErrorStatusCannotConnect` | `WebErrorStatus.cannotConnect` |
| `WebErrorStatus.WebErrorStatusHostNameNotResolved` | `WebErrorStatus.hostNameNotResolved` |
| `WebErrorStatus.WebErrorStatusOperationCanceled` | `WebErrorStatus.operationCanceled` |
| `WebErrorStatus.WebErrorStatusRedirectFailed` | `WebErrorStatus.redirectFailed` |
| `WebErrorStatus.WebErrorStatusUnexpectedError` | `WebErrorStatus.unexpectedError` |
| `WebErrorStatus.WebErrorStatusValidAuthenticationCredentialsRequired` | `WebErrorStatus.validAuthenticationCredentialsRequired` |
| `WebErrorStatus.WebErrorStatusValidProxyAuthenticationRequired` | `WebErrorStatus.validProxyAuthenticationRequired` |

## Removed or changed API

| 0.4.x | 1.x |
| --- | --- |
| top-level `getButton(int)` | Removed; inline the mapping if used. |
| Single-subscription streams (`url`, `title`, `historyChanged`, `securityStateChanged`, `webMessage`, `onLoadError`) | All controller streams are broadcast; no buffering/replay; `done` on dispose. |
| Pre-init method call: debug `assert` / release `LateInitializationError` crash | `StateError` with an actionable message in all build modes. |
| `initialize()` after `dispose()`: silent return | Throws `StateError`. |
| Failed `initialize()`: `ready`/`dispose()` could hang forever | Future completes with the error; retry allowed; `ready` never hangs. |
| Unknown native `WebErrorStatus` index: `RangeError` in the event handler | Maps to `WebErrorStatus.unknown`. |
| Default WebView2 context menus: enabled | Disabled at creation; opt in with `setDefaultContextMenusEnabled(true)` (>=1.1.0). |

## New API in 1.x (does not exist in 0.4.x)

- `controller.focus()`, static `WebviewController.releaseFocus()`
- `controller.onFocusChanged` (`Stream<bool>`), `controller.hasNativeFocus`
- `controller.setSize(Size, {double scaleFactor, Offset offset})` for headless
  use and custom texture embedding
- `controller.getCookies` / `setCookie` / `deleteCookies` and the
  `WebviewCookie` model (alongside the existing `clearCookies`)
- `controller.setDefaultContextMenusEnabled(bool)` (>=1.1.0)
- `controller.onDownloadEvent` (`Stream<WebviewDownloadEvent>`)

## Environment and SDK floors

| Item | 0.4.x | 1.x |
| --- | --- | --- |
| Dart / Flutter | Older floors | `sdk: ^3.12.0`, `flutter: >=3.44.0` |
| Toolchain | VS2019/2022, propagated `cxx_std_20` to the app | VS2022, C++23 internal, no propagation (add `target_compile_features` to the runner if it relied on it) |
| `initializeEnvironment` | One-shot | Reference counted; reconfigurable after all controllers are disposed; throws `PlatformException` while any controller is alive |
