You are working in a Flutter Windows desktop project whose `pubspec.yaml`
already depends on `webview_flutter_windows: ^1.1.0` (and `flutter`).

Create `lib/browser_pane.dart`: a widget embedding a web browser view using
the webview_flutter_windows package. Requirements:

1. Show a progress indicator until the browser is ready.
2. Show a URL readout that follows navigation.
3. Handle load errors with a retry button.
4. Users must be able to right-click images and copy them.
5. If the machine lacks the WebView2 runtime, show an install prompt
   instead of the browser.

Do not ask questions; produce the complete file.
