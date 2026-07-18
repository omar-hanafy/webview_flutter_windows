---
name: test-webview-windows
description: Use when writing or fixing Dart/Flutter tests for code that uses webview_flutter_windows - widget or unit tests involving WebviewController or the Webview widget, tests that hang on initialize(), throw MissingPluginException, or need to fake navigation events, web messages, load errors, or focus changes without a Windows machine or a real WebView2 runtime.
---

# Test code that uses webview_flutter_windows

There is no native side in `flutter test`, so every test must fake the
package's platform channels. The contract is exact; guessing it produces
tests that hang or crash. Use the ready-made fake in
`references/webview_channel_fake.dart` (copy it into the project, e.g.
`test/support/webview_channel_fake.dart`).

## The channel contract (why the fake looks the way it does)

- Plugin channel `io.jns.webview.win`: `initialize` must return a **map**
  `{'textureId': <int>}` (returning a bare int crashes the controller);
  `dispose` arrives here with the texture id.
- Per-instance method channel `io.jns.webview.win/<textureId>`: every
  controller method (`loadUrl`, `executeScript`, ...) lands here.
- Event channel `io.jns.webview.win/<textureId>/events`: the controller
  subscribes on initialize; native events are maps
  `{'type': ..., 'value': ...}`. Without a mock stream handler, the
  subscription itself errors.

## Rules

1. Install the fake **before** calling `initialize()` (in `setUp` or at the
   start of the test).
2. In `testWidgets`, wrap `initialize()` and `dispose()` in
   `tester.runAsync(...)`. Widget-test bodies run in a fake-async zone where
   platform-channel futures are not driven; awaiting them directly hangs.
   Plain `test()` bodies do not need this.
3. In `testWidgets`, after `emit...`-ing an event, settle real microtasks
   before pumping: the event crosses real-async zones because the channel
   was subscribed inside `runAsync`. The incantation is
   `await tester.runAsync(() => Future<void>.delayed(Duration.zero));`
   followed by `await tester.pump();`. Plain `test()` bodies only need
   `await Future<void>.delayed(Duration.zero);`.
4. Dispose controllers at the end of each test (streams close, no leaks).
5. Uninstall handlers in `tearDown` so tests stay independent.

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
    await tester.pumpWidget(const MaterialApp(home: BrowserPane()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Let the controller's initialize() future complete for real.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.byKey(const Key('url-field')), findsOneWidget);

    // Drive a native event and assert the UI reacted (rule 3: settle real
    // microtasks, then pump the fake ones).
    fake.emitUrlChanged('https://example.com/dashboard');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  });
}
```

If the widget exposes its controller, the sharper form is
`await tester.runAsync(() => controller.initialize());` before pumping the
widget, then assertions need no timing tricks.

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
| Type error/crash during `initialize()` | Fake returned a bare int or wrong shape | Return `{'textureId': <int>}` (the fake does) |
| `MissingPluginException` | Fake not installed before the call | Install in `setUp` first |
| Events never arrive in test | Listener attached after `emit...`, or event sink not connected | Subscribe first; emit only after `initialize()` completed |
| Event emitted but assertion still sees the old state (`testWidgets`) | Delivery microtask not run in the fake-async zone | Rule 3: `runAsync` a zero delay, then `pump()` |
| Second test bleeds behavior from the first | Handlers left installed | `fake.uninstall()` in `tearDown` |
| Asserting on rendered web content | There is none in tests (texture is fake) | Assert on your widgets and on recorded calls/events instead |

The package's own suite (`test/webview_flutter_windows_test.dart` in the
repo) uses exactly this pattern and is the reference for advanced cases
(permission round-trips, focus coordination, pointer forwarding).
