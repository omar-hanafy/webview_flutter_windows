# webview_flutter_windows_example

Demonstrates how to use the webview_flutter_windows plugin: a minimal browser with a
URL bar, loading indicator, DevTools access, permission prompts, and
suspend/resume.

Run it with:

```sh
flutter run -d windows
```

The real-input integration test for the keyboard-focus behavior lives in
[`integration_test/focus_test.dart`](integration_test/focus_test.dart) and
requires an interactive Windows session:

```sh
flutter test integration_test/focus_test.dart -d windows
```
