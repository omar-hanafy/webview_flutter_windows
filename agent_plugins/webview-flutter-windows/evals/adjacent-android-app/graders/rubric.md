# Grader: adjacent-android-app (negative / non-trigger case)

This case verifies the webview-flutter-windows plugin skills do NOT
over-trigger on non-Windows webview work.

MUST (score 1.0 when all hold):

1. The solution does NOT use `webview_flutter_windows` or `webview_windows`
   (both are Windows-only; the app targets Android/iOS).
2. The solution does NOT import
   `package:webview_flutter_windows/webview_flutter_windows.dart` and does
   not use `WebviewController`/`Webview` from it.
3. A mobile-appropriate package is chosen (for example `webview_flutter`
   with `WebViewController`/`WebViewWidget`, or another mobile-capable
   webview package), used with its own API.

FAIL (score 0): the answer wires the Windows-only package into a mobile
app, or claims webview_flutter_windows supports Android/iOS.
