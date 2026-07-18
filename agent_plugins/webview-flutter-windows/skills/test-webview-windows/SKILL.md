---
name: test-webview-windows
description: Use when writing or fixing Dart/Flutter tests for code that uses webview_flutter_windows - widget or unit tests involving WebviewController or the Webview widget, tests that hang on initialize(), throw MissingPluginException or "Invalid argument: Instance of 'MockStreamHandlerEventSink'", or need to fake navigation events, web messages, load errors, or focus changes without a Windows machine or a real WebView2 runtime.
---

# Test code that uses webview_flutter_windows

There is no native side in `flutter test`, so every test must fake the
package's platform channels. The contract is exact; guessing it produces
tests that hang or crash.

**Do not hand-write your own fake.** Copy the ready-made one,
`references/webview_channel_fake.dart` in this skill's directory (skills
load with their base directory path), into the project as
`test/support/webview_channel_fake.dart`. It is verified against the real
package. Only when that file is out of reach, use the minimal inline fake
below, verbatim.

## The channel contract (why the fake looks the way it does)

- Plugin channel `io.jns.webview.win`: `initialize` must return a **map**
  `{'textureId': <int>}` (a bare int or a generic success reply crashes the
  controller); `dispose` arrives here with the texture id.
- Per-instance method channel `io.jns.webview.win/<textureId>`: every
  controller method (`loadUrl`, `executeScript`, ...) lands here.
- Event channel `io.jns.webview.win/<textureId>/events`: the controller
  subscribes on initialize; native events are maps
  `{'type': ..., 'value': ...}`. Without a mock stream handler, the
  subscription itself errors.

## Rules

1. Install the fake **before** calling `initialize()` (in `setUp` or at the
   start of the test), and uninstall in `tearDown`.
2. In `testWidgets`, wrap `initialize()` and `dispose()` in
   `tester.runAsync(...)`. Widget-test bodies run in a fake-async zone where
   platform-channel futures are not driven; awaiting them directly hangs.
   Plain `test()` bodies do not need this.
3. In `testWidgets`, after emitting an event, settle real microtasks before
   pumping: `await tester.runAsync(() => Future<void>.delayed(Duration.zero));`
   then `await tester.pump();`. In plain `test()` bodies,
   `await Future<void>.delayed(Duration.zero);` suffices.
4. In `MockStreamHandler.inline`, the `onListen`/`onCancel` callbacks MUST
   use block bodies. An arrow body leaks the assignment's value into the
   reply envelope and fails with
   `PlatformException(error, Invalid argument: Instance of 'MockStreamHandlerEventSink')`.
5. Pump widgets that contain material widgets (like `TextField`) inside
   `MaterialApp(home: Scaffold(body: ...))`, or the test dies with
   "No Material widget found".
6. Dispose controllers at the end of each test (streams close, no leaks).

## Minimal inline fake (fallback when the reference file is unavailable)

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal fake native side for webview_flutter_windows.
class MinimalWebviewFake {
  MinimalWebviewFake({this.textureId = 1});

  final int textureId;
  final List<MethodCall> calls = <MethodCall>[];
  MockStreamHandlerEventSink? sink;

  static const MethodChannel _plugin = MethodChannel('io.jns.webview.win');

  TestDefaultBinaryMessenger get _m =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    _m.setMockMethodCallHandler(_plugin, (call) async {
      calls.add(call);
      // 'initialize' MUST answer with this exact map shape.
      return call.method == 'initialize'
          ? <String, dynamic>{'textureId': textureId}
          : null;
    });
    _m.setMockMethodCallHandler(
      MethodChannel('io.jns.webview.win/$textureId'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
    _m.setMockStreamHandler(
      EventChannel('io.jns.webview.win/$textureId/events'),
      // Block bodies REQUIRED here (rule 4).
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          sink = events;
        },
        onCancel: (arguments) {
          sink = null;
        },
      ),
    );
  }

  void uninstall() {
    _m.setMockMethodCallHandler(_plugin, null);
    _m.setMockMethodCallHandler(
      MethodChannel('io.jns.webview.win/$textureId'),
      null,
    );
    sink = null;
  }

  /// Injects a native event, e.g. {'type': 'urlChanged', 'value': 'https://x'}.
  void emit(Map<String, dynamic> event) => sink!.success(event);
}
```

(The reference fake adds typed `emit...` helpers, call logs per channel,
failure injection via `onInitialize`/`onInstanceCall`, and
`getWebViewVersion` control. Prefer it.)

## Widget test example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/webview_channel_fake.dart';
import 'package:my_app/browser_pane.dart'; // widget owning a WebviewController

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WebviewChannelFake fake;

  setUp(() => fake = WebviewChannelFake()..install());
  tearDown(() => fake.uninstall());

  testWidgets('shows spinner, then content after initialize', (tester) async {
    // Rule 5: Material ancestor for TextField and friends.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BrowserPane())),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Rule 2/3: let the controller's initialize() future complete for real.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.byKey(const Key('url-field')), findsOneWidget);

    // Drive a native event and assert the UI reacted (rule 3 again).
    fake.emitUrlChanged('https://example.com/dashboard');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  });
}
```

If the widget exposes its controller, the sharper form is
`await tester.runAsync(() => controller.initialize());` before pumping,
then assertions need no timing tricks.

## Unit test example (no widgets)

```dart
test('retry logic reacts to load errors', () async {
  final fake = WebviewChannelFake()..install();
  addTearDown(fake.uninstall);

  final controller = WebviewController();
  await controller.initialize();

  final errors = <WebErrorStatus>[];
  controller.onLoadError.listen(errors.add);   // subscribe BEFORE emitting

  fake.emitLoadError(WebErrorStatus.timeout);
  await Future<void>.delayed(Duration.zero);   // let the event deliver

  expect(errors, [WebErrorStatus.timeout]);
  await controller.dispose();
});
```

## Assert outgoing calls

`fake.pluginCalls` and `fake.instanceCalls` record every `MethodCall`:

```dart
await controller.loadUrl('https://a');
expect(fake.instanceCalls.single.method, 'loadUrl');
expect(fake.instanceCalls.single.arguments, 'https://a');
```

Simulate native failures by throwing from the handlers:
`fake.onInitialize = () => throw PlatformException(code: 'environment_creation_failed');`
or per-method via `fake.onInstanceCall`.

## Pitfalls

| Symptom | Cause | Fix |
| --- | --- | --- |
| Test hangs on `initialize()` | Awaited inside the fake-async zone of `testWidgets` | Wrap in `tester.runAsync` (rule 2) |
| Type error/crash during `initialize()` | Fake returned a bare int or wrong shape | Return `{'textureId': <int>}` |
| `PlatformException(error, Invalid argument: Instance of 'MockStreamHandlerEventSink')` | Arrow body in `onListen`/`onCancel` leaked the sink into the reply envelope | Rule 4: block bodies |
| "No Material widget found" | Pumped a `TextField`-bearing widget without Material | Rule 5: `MaterialApp(home: Scaffold(...))` |
| `MissingPluginException` | Fake not installed before the call | Install in `setUp` first |
| Events never arrive in test | Listener attached after emitting, or event sink not connected | Subscribe first; emit only after `initialize()` completed |
| Event emitted but assertion sees old state (`testWidgets`) | Delivery microtask not run in the fake-async zone | Rule 3: `runAsync` a zero delay, then `pump()` |
| Second test bleeds behavior into the first | Handlers left installed | `uninstall()` in `tearDown` |
| Asserting on rendered web content | There is none in tests (texture is fake) | Assert on your widgets and on recorded calls/events instead |

The package's own suite (`test/webview_flutter_windows_test.dart` in the
repo) uses exactly this pattern and is the reference for advanced cases
(permission round-trips, focus coordination, pointer forwarding).
