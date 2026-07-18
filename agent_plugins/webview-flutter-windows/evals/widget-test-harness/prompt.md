You are working in a Flutter project whose `pubspec.yaml` depends on
`webview_flutter_windows: ^1.1.0`, with this widget.

`lib/browser_pane.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

/// Shows a URL field once the webview controller is ready.
class BrowserPane extends StatefulWidget {
  const BrowserPane({super.key});

  @override
  State<BrowserPane> createState() => _BrowserPaneState();
}

class _BrowserPaneState extends State<BrowserPane> {
  final controller = WebviewController();

  @override
  void initState() {
    super.initState();
    controller.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        const TextField(key: Key('url-field')),
        Expanded(child: Webview(controller)),
      ],
    );
  }
}
```

Write `test/browser_pane_test.dart` with widget tests proving: (1) a spinner
shows before initialization completes, (2) the URL field appears after
initialization completes. The tests must run on any platform, so mock or
fake whatever the webview_flutter_windows package needs. Do not ask
questions; produce the complete test file (plus any support file you need).
