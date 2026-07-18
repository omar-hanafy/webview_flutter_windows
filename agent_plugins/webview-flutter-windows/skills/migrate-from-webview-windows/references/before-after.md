# Worked migration example

A representative 0.4.x widget with the three classic patterns: subscribing
after navigation (relying on buffered streams), prefixed `WebErrorStatus`
names, and a `window_manager` focus workaround for upstream issue 230.

## Before (webview_windows 0.4.x)

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

    // Relied on single-subscription buffering: subscribe AFTER loadUrl.
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
      // Workaround for upstream issue 230: re-activate the window after
      // webview clicks so keyboard shortcuts keep working.
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

## After (webview_flutter_windows 1.x)

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

class DashboardPane extends StatefulWidget {
  const DashboardPane({super.key, required this.dashboardUrl});
  final String dashboardUrl;

  @override
  State<DashboardPane> createState() => _DashboardPaneState();
}

class _DashboardPaneState extends State<DashboardPane> {
  final _controller = WebviewController();
  StreamSubscription<WebErrorStatus>? _errorSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
    } on PlatformException catch (e) {
      debugPrint('webview init failed: ${e.code}');
      return; // Surface an error UI in a real app.
    }

    // Broadcast streams drop unheard events: subscribe BEFORE navigating.
    _controller.url.listen((url) => debugPrint('now at $url'));
    _errorSub = _controller.onLoadError.listen((status) {
      if (status == WebErrorStatus.timeout ||
          status == WebErrorStatus.disconnected) {
        _scheduleRetry();
      }
    });

    await _controller.loadUrl(widget.dashboardUrl);

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
    // No focus workaround: 1.x keeps the window active and returns keyboard
    // focus to Flutter automatically (upstream issue 230 is fixed natively).
    return Webview(_controller);
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _controller.dispose();
    super.dispose();
  }
}
```

## Diff summary

- `pubspec.yaml`: `webview_windows: ^0.4.0` -> `webview_flutter_windows:
  ^1.1.1`; `window_manager` removed when it existed only for the workaround;
  SDK floor raised to `^3.12.0`.
- Import swapped to `package:webview_flutter_windows/webview_flutter_windows.dart`.
- `WebErrorStatusTimeout` / `WebErrorStatusDisconnected` ->
  `timeout` / `disconnected`.
- `url.listen` moved before `loadUrl` (no more buffering).
- `Listener` + `windowManager.focus()` workaround deleted.
- `initialize()` wrapped in try/catch (failures now complete the future).
