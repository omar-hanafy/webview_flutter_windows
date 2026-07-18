You are working in a Flutter project with exactly these two files.

`pubspec.yaml`:

```yaml
name: legacy_kiosk
description: Internal kiosk shell that embeds a web dashboard on Windows.
publish_to: 'none'
version: 2.3.0

environment:
  sdk: '>=2.17.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  webview_windows: ^0.4.0
  window_manager: ^0.3.7

dev_dependencies:
  flutter_test:
    sdk: flutter
```

`lib/dashboard_pane.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:window_manager/window_manager.dart';

class DashboardPane extends StatefulWidget {
  const DashboardPane({super.key, required this.dashboardUrl});
  final String dashboardUrl;

  @override
  State<DashboardPane> createState() => _DashboardPaneState();
}

class _DashboardPaneState extends State<DashboardPane> {
  final _controller = WebviewController();
  StreamSubscription<WebErrorStatus>? _errorSub;
  Timer? _refocusTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _controller.initialize();
    await _controller.loadUrl(widget.dashboardUrl);

    // The url stream buffers events until we listen, so subscribing after
    // loadUrl still delivers the first navigation.
    _controller.url.listen((url) => debugPrint('now at $url'));

    _errorSub = _controller.onLoadError.listen((status) {
      if (status == WebErrorStatus.WebErrorStatusTimeout ||
          status == WebErrorStatus.WebErrorStatusDisconnected) {
        _scheduleRetry();
      }
    });

    if (mounted) setState(() {});
  }

  void _scheduleRetry() {
    Timer(const Duration(seconds: 5), () => _controller.reload());
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Listener(
      // Workaround for jnschulze/flutter-webview-windows#230: clicking the
      // webview deactivates the window, so we re-activate it shortly after
      // every click to keep keyboard shortcuts working.
      onPointerDown: (_) {
        _refocusTimer?.cancel();
        _refocusTimer = Timer(const Duration(milliseconds: 120), () async {
          await windowManager.focus();
        });
      },
      child: Webview(_controller),
    );
  }

  @override
  void dispose() {
    _refocusTimer?.cancel();
    _errorSub?.cancel();
    _controller.dispose();
    super.dispose();
  }
}
```

This app still depends on the discontinued webview_windows package. Migrate
it to the maintained fork webview_flutter_windows (latest). Produce the full
updated contents of pubspec.yaml and lib/dashboard_pane.dart, and list every
behavioral difference you accounted for. Work only from what you know; do
not ask questions.
