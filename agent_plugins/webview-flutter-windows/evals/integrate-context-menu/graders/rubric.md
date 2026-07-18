# Grader: integrate-context-menu

Score 1.0 only if ALL MUST items hold.
This case exercises the `integrate-webview-windows` skill.

MUST:

1. Calls `await controller.setDefaultContextMenusEnabled(true)` after
   `initialize()` and before the navigation that should show menus. This is
   the deciding item: webview_flutter_windows disables WebView2's default
   context menus at creation, so right-click copy-image does NOT work
   without this call. An answer claiming menus work "out of the box" fails.
2. Uses the real API: `WebviewController`, `initialize()`, `Webview(...)`
   widget, `controller.value.isInitialized` gating, `controller.dispose()`
   in `dispose()`. No APIs invented or borrowed from webview_flutter.
3. Subscribes to `controller.url` (and `onLoadError`) BEFORE calling
   `loadUrl` (broadcast streams drop unheard events).
4. Checks `WebviewController.getWebViewVersion()` for null and/or catches
   `PlatformException` with code `environment_creation_failed` from
   `initialize()`, showing install guidance for the WebView2 runtime.

SHOULD:

5. Retry path re-navigates (reload/loadUrl) and re-attempts initialize when
   initialization itself failed (initialize() is retryable in 1.x).
6. Load errors observed via the `onLoadError` stream
   (`Stream<WebErrorStatus>`, lowerCamelCase values such as
   `WebErrorStatus.timeout`).

FAIL (score 0): missing item 1, or the file is built on a different
package's API (NavigationDelegate, WebViewWidget, InAppWebView, etc.).
