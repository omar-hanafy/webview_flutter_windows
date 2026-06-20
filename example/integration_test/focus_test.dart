// Real-input integration test for the window focus fix
// (https://github.com/jnschulze/flutter-webview-windows/issues/230).
//
// Unlike regular widget tests, this test injects REAL Win32 input through
// SendInput and asserts on REAL window manager state (foreground window,
// focused HWND). It verifies that:
//
//  1. Clicking inside the webview does NOT deactivate the Flutter window.
//  2. Keyboard input reaches the web page after clicking it.
//  3. Clicking back on Flutter UI returns Win32 focus to the Flutter view
//     immediately (no second click / window re-activation needed).
//  4. Typing then reaches Flutter widgets again, and the whole cycle can
//     repeat.
//
// Run with: flutter test integration_test/focus_test.dart -d windows

import 'dart:ffi';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';
import 'package:win32/win32.dart';

const String _testPageHtml = '''
<!DOCTYPE html>
<html>
  <body style="margin:0;background:#ffffff">
    <input id="i" autocomplete="off"
           style="position:absolute;inset:0;width:100%;height:100%;font-size:32px;border:none;outline:none" />
  </body>
</html>
''';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'webview click keeps window active and keyboard focus round-trips',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      // Without this, the live test binding swallows real device pointer
      // events instead of dispatching them to the widget tree. The binding
      // verifies the flag is restored at the END OF THE TEST BODY (before
      // tearDown callbacks run), so it must be reset in a finally block.
      binding.shouldPropagateDevicePointerEvents = true;

      final webviewController = WebviewController();
      try {
        await webviewController.initialize();

        final navigationCompleted = webviewController.loadingState.firstWhere(
          (state) => state == LoadingState.navigationCompleted,
        );

        final textController = TextEditingController();
        const textFieldKey = Key('flutter-text-field');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      key: textFieldKey,
                      controller: textController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Flutter text field',
                      ),
                    ),
                  ),
                  Expanded(child: Webview(webviewController)),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        // Locate the native windows.
        final runnerClassName = 'FLUTTER_RUNNER_WIN32_WINDOW'.toPcwstr();
        final viewClassName = 'FLUTTERVIEW'.toPcwstr();
        final topHwnd = FindWindow(runnerClassName, null).value;
        expect(
          topHwnd.address,
          isNot(equals(0)),
          reason: 'top-level Flutter runner window not found',
        );
        final viewHwnd = FindWindowEx(topHwnd, null, viewClassName, null).value;
        expect(
          viewHwnd.address,
          isNot(equals(0)),
          reason: 'FLUTTERVIEW child window not found',
        );
        free(runnerClassName);
        free(viewClassName);

        // Deterministic geometry + make sure we start in the foreground.
        SetWindowPos(topHwnd, null, 40, 40, 1000, 700, SWP_SHOWWINDOW);
        await _waitUntil(tester, () async {
          if (GetForegroundWindow() == topHwnd) {
            return true;
          }
          _forceForeground(topHwnd);
          return GetForegroundWindow() == topHwnd;
        }, reason: 'test window must become the foreground window');
        await _delay(800);
        await tester.pump();

        // Load the test page and wait until it is ready.
        await webviewController.loadStringContent(_testPageHtml);
        await navigationCompleted.timeout(const Duration(seconds: 30));
        await _delay(1500);
        await tester.pump();

        final webviewCenter = _screenPoint(
          tester,
          find.byType(Webview),
          viewHwnd,
        );
        final textFieldCenter = _screenPoint(
          tester,
          find.byKey(textFieldKey),
          viewHwnd,
        );

        // ----------------------------------------------------------------
        // 1. Click inside the webview.
        // ----------------------------------------------------------------
        _clickAt(webviewCenter);
        await _waitUntil(
          tester,
          () async => webviewController.hasNativeFocus,
          reason:
              'webview should hold native focus after being clicked '
              '(focus event from WebView2)',
        );

        // The original #230 symptom: the whole window lost activation here.
        expect(
          GetForegroundWindow(),
          equals(topHwnd),
          reason:
              'clicking the webview must not deactivate the host window '
              '(jnschulze/flutter-webview-windows#230)',
        );

        final webviewFocusHwnd = _globalFocusHwnd();
        expect(
          webviewFocusHwnd,
          isNot(equals(viewHwnd)),
          reason: 'WebView2 should hold real Win32 focus while typing',
        );
        expect(
          IsChild(viewHwnd, webviewFocusHwnd),
          isTrue,
          reason:
              'the WebView2 input window must live inside the Flutter '
              'view window tree (reparenting fix)',
        );

        // ----------------------------------------------------------------
        // 2. Real typing reaches the web page.
        // ----------------------------------------------------------------
        _typeText('ab');
        await _waitUntil(
          tester,
          () async => await _webInputValue(webviewController) == 'ab',
          reason: 'keystrokes should reach the web page input',
        );

        // ----------------------------------------------------------------
        // 3. Click the Flutter text field; focus must return immediately.
        // ----------------------------------------------------------------
        _clickAt(textFieldCenter);
        await _waitUntil(
          tester,
          () async => _globalFocusHwnd() == viewHwnd,
          reason:
              'Win32 focus should return to the Flutter view as soon as '
              'Flutter UI is clicked (no second click required)',
        );
        expect(
          GetForegroundWindow(),
          equals(topHwnd),
          reason: 'window must stay active during the focus handover',
        );

        _typeText('cd');
        await _waitUntil(
          tester,
          () async => textController.text.contains('cd'),
          reason: 'typing after clicking Flutter UI must reach the TextField',
        );

        // ----------------------------------------------------------------
        // 4. Round trip: back into the webview.
        // ----------------------------------------------------------------
        _clickAt(webviewCenter);
        await _waitUntil(
          tester,
          () async => webviewController.hasNativeFocus,
          reason: 'webview should be focusable again after the round trip',
        );
        _typeText('ef');
        await _waitUntil(tester, () async {
          final value = await _webInputValue(webviewController);
          return value is String && value.contains('ef');
        }, reason: 'keystrokes should reach the web page input again');
        expect(GetForegroundWindow(), equals(topHwnd));

        // Tear down cleanly.
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await webviewController.dispose();
      } finally {
        binding.shouldPropagateDevicePointerEvents = false;
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<dynamic> _webInputValue(WebviewController controller) {
  return controller.executeScript("document.getElementById('i').value");
}

/// Computes the on-screen (physical) position of the center of [finder]
/// inside the Flutter view window.
math.Point<int> _screenPoint(
  WidgetTester tester,
  Finder finder,
  HWND viewHwnd,
) {
  final centerLogical = tester.getCenter(finder);
  final dpr = tester.view.devicePixelRatio;
  final point = calloc<POINT>();
  try {
    point.ref.x = (centerLogical.dx * dpr).round();
    point.ref.y = (centerLogical.dy * dpr).round();
    ClientToScreen(viewHwnd, point);
    return math.Point<int>(point.ref.x, point.ref.y);
  } finally {
    calloc.free(point);
  }
}

/// The HWND holding keyboard focus on the foreground input queue.
HWND _globalFocusHwnd() {
  final info = calloc<GUITHREADINFO>();
  try {
    info.ref.cbSize = sizeOf<GUITHREADINFO>();
    if (!GetGUIThreadInfo(0, info).value) {
      return HWND(nullptr);
    }
    return info.ref.hwndFocus;
  } finally {
    calloc.free(info);
  }
}

/// Brings [hwnd] to the foreground. Simulates an ALT tap first, which lifts
/// the SetForegroundWindow lock for the calling process (documented Win32
/// behavior), making this reliable on CI runners.
void _forceForeground(HWND hwnd) {
  final alt = calloc<INPUT>(2);
  try {
    alt[0].type = INPUT_KEYBOARD;
    alt[0].Anonymous.ki.wVk = VK_MENU;
    alt[1].type = INPUT_KEYBOARD;
    alt[1].Anonymous.ki.wVk = VK_MENU;
    alt[1].Anonymous.ki.dwFlags = KEYEVENTF_KEYUP;
    SendInput(2, alt, sizeOf<INPUT>());
  } finally {
    calloc.free(alt);
  }
  SetForegroundWindow(hwnd);
}

/// Sends a real (hardware-level) left mouse click at the given screen point.
void _clickAt(math.Point<int> screenPoint) {
  final screenW = GetSystemMetrics(SM_CXSCREEN);
  final screenH = GetSystemMetrics(SM_CYSCREEN);
  final nx = (screenPoint.x * 65535 / (screenW - 1)).round();
  final ny = (screenPoint.y * 65535 / (screenH - 1)).round();

  final inputs = calloc<INPUT>(3);
  try {
    inputs[0].type = INPUT_MOUSE;
    inputs[0].Anonymous.mi.dx = nx;
    inputs[0].Anonymous.mi.dy = ny;
    inputs[0].Anonymous.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;

    inputs[1].type = INPUT_MOUSE;
    inputs[1].Anonymous.mi.dx = nx;
    inputs[1].Anonymous.mi.dy = ny;
    inputs[1].Anonymous.mi.dwFlags =
        MOUSEEVENTF_LEFTDOWN | MOUSEEVENTF_ABSOLUTE;

    inputs[2].type = INPUT_MOUSE;
    inputs[2].Anonymous.mi.dx = nx;
    inputs[2].Anonymous.mi.dy = ny;
    inputs[2].Anonymous.mi.dwFlags = MOUSEEVENTF_LEFTUP | MOUSEEVENTF_ABSOLUTE;

    SendInput(3, inputs, sizeOf<INPUT>());
  } finally {
    calloc.free(inputs);
  }
}

/// Sends real key taps for the given lowercase latin text.
void _typeText(String text) {
  for (final codeUnit in text.toUpperCase().codeUnits) {
    final inputs = calloc<INPUT>(2);
    try {
      inputs[0].type = INPUT_KEYBOARD;
      inputs[0].Anonymous.ki.wVk = VIRTUAL_KEY(codeUnit);

      inputs[1].type = INPUT_KEYBOARD;
      inputs[1].Anonymous.ki.wVk = VIRTUAL_KEY(codeUnit);
      inputs[1].Anonymous.ki.dwFlags = KEYEVENTF_KEYUP;

      SendInput(2, inputs, sizeOf<INPUT>());
    } finally {
      calloc.free(inputs);
    }
  }
}

Future<void> _delay(int milliseconds) {
  return Future<void>.delayed(Duration(milliseconds: milliseconds));
}

Future<void> _waitUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
    await _delay(150);
  }
  fail('Timed out waiting for: $reason');
}
