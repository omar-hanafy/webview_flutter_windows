import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

const MethodChannel _pluginChannel = MethodChannel('io.jns.webview.win');
const StandardMethodCodec _codec = StandardMethodCodec();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late List<MethodCall> pluginLog;
  late List<MethodCall> instanceLog;
  MockStreamHandlerEventSink? eventSink;

  /// Installs a mock native side: the plugin channel creates instances with
  /// [textureId], the per-instance method channel records calls into
  /// [instanceLog] and replies with [instanceResults] (per method name), and
  /// the per-instance event channel exposes its sink through [eventSink].
  void mockNativeSide({
    int textureId = 1,
    Object? Function(MethodCall call)? onInstanceCall,
    Object? Function()? onInitialize,
  }) {
    messenger.setMockMethodCallHandler(_pluginChannel, (call) async {
      pluginLog.add(call);
      switch (call.method) {
        case 'initialize':
          if (onInitialize != null) {
            return onInitialize();
          }
          return <String, dynamic>{'textureId': textureId};
        default:
          return null;
      }
    });

    messenger.setMockMethodCallHandler(
      MethodChannel('io.jns.webview.win/$textureId'),
      (call) async {
        instanceLog.add(call);
        return onInstanceCall?.call(call);
      },
    );

    messenger.setMockStreamHandler(
      EventChannel('io.jns.webview.win/$textureId/events'),
      // Block bodies on purpose: the mock encodes the callback's runtime
      // return value into the `listen`/`cancel` reply envelope, and an arrow
      // body would leak the (unencodable) assignment value.
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          eventSink = events;
        },
        onCancel: (arguments) {
          eventSink = null;
        },
      ),
    );
  }

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    pluginLog = <MethodCall>[];
    instanceLog = <MethodCall>[];
    eventSink = null;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_pluginChannel, null);
  });

  group('initialize', () {
    test('creates the native instance and becomes initialized', () async {
      mockNativeSide();
      final controller = WebviewController();

      expect(controller.value.isInitialized, isFalse);
      await controller.initialize();

      expect(controller.value.isInitialized, isTrue);
      expect(pluginLog.map((c) => c.method), ['initialize']);
      await expectLater(controller.ready, completes);

      await controller.dispose();
    });

    test('is a no-op when already initialized', () async {
      mockNativeSide();
      final controller = WebviewController();
      await controller.initialize();
      await controller.initialize();

      expect(pluginLog.where((c) => c.method == 'initialize'), hasLength(1));
      await controller.dispose();
    });

    test('concurrent calls join the in-flight initialization', () async {
      mockNativeSide();
      final controller = WebviewController();

      final first = controller.initialize();
      final second = controller.initialize();
      await Future.wait([first, second]);

      expect(controller.value.isInitialized, isTrue);
      expect(pluginLog.where((c) => c.method == 'initialize'), hasLength(1));
      await controller.dispose();
    });

    test('failure surfaces the error, leaves the controller uninitialized '
        'and allows a retry', () async {
      var fail = true;
      mockNativeSide(
        onInitialize: () {
          if (fail) {
            throw PlatformException(code: 'webview_creation_failed');
          }
          return <String, dynamic>{'textureId': 1};
        },
      );
      final controller = WebviewController();

      await expectLater(
        controller.initialize(),
        throwsA(isA<PlatformException>()),
      );
      expect(controller.value.isInitialized, isFalse);

      fail = false;
      await controller.initialize();
      expect(controller.value.isInitialized, isTrue);

      await controller.dispose();
    });

    test('throws StateError after dispose', () async {
      mockNativeSide();
      final controller = WebviewController();
      await controller.dispose();

      expect(controller.initialize, throwsStateError);
    });
  });

  group('uninitialized controller', () {
    test('methods throw an actionable StateError', () async {
      final controller = WebviewController();
      await expectLater(controller.loadUrl('https://a'), throwsStateError);
      await expectLater(controller.reload(), throwsStateError);
      await expectLater(controller.executeScript('1'), throwsStateError);
    });
  });

  group('methods', () {
    late WebviewController controller;

    setUp(() async {
      mockNativeSide();
      controller = WebviewController();
      await controller.initialize();
      instanceLog.clear();
    });

    tearDown(() async {
      await controller.dispose();
    });

    MethodCall single() {
      expect(instanceLog, hasLength(1));
      return instanceLog.single;
    }

    test('loadUrl', () async {
      await controller.loadUrl('https://flutter.dev');
      expect(
        single(),
        isMethodCall('loadUrl', arguments: 'https://flutter.dev'),
      );
    });

    test('loadStringContent', () async {
      await controller.loadStringContent('<html></html>');
      expect(
        single(),
        isMethodCall('loadStringContent', arguments: '<html></html>'),
      );
    });

    test('navigation methods', () async {
      await controller.reload();
      await controller.stop();
      await controller.goBack();
      await controller.goForward();
      expect(instanceLog.map((c) => c.method), [
        'reload',
        'stop',
        'goBack',
        'goForward',
      ]);
    });

    test('executeScript decodes the JSON result', () async {
      mockNativeSide(
        onInstanceCall: (call) {
          if (call.method == 'executeScript') {
            return '{"a": 1}';
          }
          return null;
        },
      );
      final result = await controller.executeScript('document.title');
      expect(result, {'a': 1});
    });

    test('executeScript returns null for a null result', () async {
      final result = await controller.executeScript('void 0');
      expect(result, isNull);
    });

    test('addScriptToExecuteOnDocumentCreated returns the script id', () async {
      mockNativeSide(
        onInstanceCall: (call) {
          if (call.method == 'addScriptToExecuteOnDocumentCreated') {
            return 'script-42';
          }
          return null;
        },
      );
      final id = await controller.addScriptToExecuteOnDocumentCreated('x');
      expect(id, 'script-42');

      await controller.removeScriptToExecuteOnDocumentCreated(id!);
      expect(
        instanceLog.last,
        isMethodCall(
          'removeScriptToExecuteOnDocumentCreated',
          arguments: 'script-42',
        ),
      );
    });

    test('postWebMessage and setUserAgent', () async {
      await controller.postWebMessage('{"x":1}');
      await controller.setUserAgent('agent');
      expect(instanceLog, [
        isMethodCall('postWebMessage', arguments: '{"x":1}'),
        isMethodCall('setUserAgent', arguments: 'agent'),
      ]);
    });

    test('cache and cookie management', () async {
      await controller.clearCookies();
      await controller.clearCache();
      await controller.setCacheDisabled(true);
      expect(instanceLog, [
        isMethodCall('clearCookies', arguments: null),
        isMethodCall('clearCache', arguments: null),
        isMethodCall('setCacheDisabled', arguments: true),
      ]);
    });

    test('openDevTools', () async {
      await controller.openDevTools();
      expect(single(), isMethodCall('openDevTools', arguments: null));
    });

    test('setBackgroundColor sends a signed 32-bit ARGB value', () async {
      await controller.setBackgroundColor(const Color(0xFF112233));
      expect(
        single(),
        isMethodCall('setBackgroundColor', arguments: 0xFF112233.toSigned(32)),
      );
    });

    test('setZoomFactor', () async {
      await controller.setZoomFactor(1.5);
      expect(single(), isMethodCall('setZoomFactor', arguments: 1.5));
    });

    test('setPopupWindowPolicy sends the policy index', () async {
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      expect(single(), isMethodCall('setPopupWindowPolicy', arguments: 1));
    });

    test('suspend and resume', () async {
      await controller.suspend();
      await controller.resume();
      expect(instanceLog.map((c) => c.method), ['suspend', 'resume']);
    });

    test('focus maps to moveFocus', () async {
      await controller.focus();
      expect(single(), isMethodCall('moveFocus', arguments: null));
    });

    test('virtual host name mapping', () async {
      await controller.addVirtualHostNameMapping(
        'assets.local',
        'C:/assets',
        WebviewHostResourceAccessKind.denyCors,
      );
      await controller.removeVirtualHostNameMapping('assets.local');
      expect(instanceLog, [
        isMethodCall(
          'setVirtualHostNameMapping',
          arguments: ['assets.local', 'C:/assets', 2],
        ),
        isMethodCall('clearVirtualHostNameMapping', arguments: 'assets.local'),
      ]);
    });

    test('getCookies decodes the cookie list', () async {
      mockNativeSide(
        onInstanceCall: (call) {
          if (call.method == 'getCookies') {
            expect(call.arguments, 'https://example.com');
            return [
              {
                'name': 'session',
                'value': 'abc',
                'domain': '.example.com',
                'path': '/',
                'expires': -1.0,
                'isSecure': true,
                'isHttpOnly': true,
                'isSession': true,
                'sameSite': 2,
              },
              {
                'name': 'theme',
                'value': 'dark',
                'domain': 'example.com',
                'path': '/app',
                'expires': 1893456000.0,
                'isSecure': false,
                'isHttpOnly': false,
                'isSession': false,
                'sameSite': 0,
              },
            ];
          }
          return null;
        },
      );

      final cookies = await controller.getCookies('https://example.com');
      expect(cookies, hasLength(2));

      expect(cookies[0].name, 'session');
      expect(cookies[0].value, 'abc');
      expect(cookies[0].domain, '.example.com');
      expect(cookies[0].path, '/');
      expect(cookies[0].expires, isNull);
      expect(cookies[0].isSession, isTrue);
      expect(cookies[0].isSecure, isTrue);
      expect(cookies[0].isHttpOnly, isTrue);
      expect(cookies[0].sameSite, WebviewCookieSameSite.strict);

      expect(
        cookies[1].expires,
        DateTime.fromMillisecondsSinceEpoch(1893456000000, isUtc: true),
      );
      expect(cookies[1].isSession, isFalse);
      expect(cookies[1].sameSite, WebviewCookieSameSite.none);
    });

    test('getCookies requests all cookies by default', () async {
      mockNativeSide(
        onInstanceCall: (call) =>
            call.method == 'getCookies' ? const <dynamic>[] : null,
      );
      final cookies = await controller.getCookies();
      expect(cookies, isEmpty);
      expect(instanceLog.last, isMethodCall('getCookies', arguments: ''));
    });

    test('getCookies maps unknown SameSite kinds to lax', () async {
      mockNativeSide(
        onInstanceCall: (call) => call.method == 'getCookies'
            ? [
                {
                  'name': 'a',
                  'value': 'b',
                  'domain': '',
                  'path': '/',
                  'expires': -1.0,
                  'isSecure': false,
                  'isHttpOnly': false,
                  'isSession': true,
                  'sameSite': 99,
                },
              ]
            : null,
      );
      final cookies = await controller.getCookies();
      expect(cookies.single.sameSite, WebviewCookieSameSite.lax);
    });

    test('setCookie sends the full wire representation', () async {
      final expires = DateTime.utc(2030, 1, 1);
      await controller.setCookie(
        WebviewCookie(
          name: 'session',
          value: 'abc',
          domain: '.example.com',
          path: '/app',
          expires: expires,
          isSecure: true,
          isHttpOnly: true,
          sameSite: WebviewCookieSameSite.strict,
        ),
      );
      expect(
        single(),
        isMethodCall(
          'setCookie',
          arguments: <String, dynamic>{
            'name': 'session',
            'value': 'abc',
            'domain': '.example.com',
            'path': '/app',
            'expires': expires.millisecondsSinceEpoch / 1000.0,
            'isSecure': true,
            'isHttpOnly': true,
            'sameSite': 2,
          },
        ),
      );
    });

    test('setCookie sends -1 expiry for session cookies', () async {
      await controller.setCookie(const WebviewCookie(name: 'a', value: 'b'));
      final args = single().arguments as Map<dynamic, dynamic>;
      expect(args['expires'], -1.0);
      expect(args['domain'], '');
      expect(args['path'], '/');
      expect(args['sameSite'], WebviewCookieSameSite.lax.index);
    });

    test('deleteCookies sends name and uri', () async {
      await controller.deleteCookies('session', uri: 'https://example.com');
      await controller.deleteCookies('theme');
      expect(instanceLog, [
        isMethodCall(
          'deleteCookies',
          arguments: ['session', 'https://example.com'],
        ),
        isMethodCall('deleteCookies', arguments: ['theme', '']),
      ]);
    });

    test(
      'setSize sends logical size and scale factor (headless use)',
      () async {
        await controller.setSize(const Size(1024, 768), scaleFactor: 2.0);
        expect(
          single(),
          isMethodCall('setSize', arguments: [1024.0, 768.0, 2.0]),
        );
      },
    );

    test('setFpsLimit', () async {
      await controller.setFpsLimit();
      await controller.setFpsLimit(30);
      expect(instanceLog, [
        isMethodCall('setFpsLimit', arguments: 0),
        isMethodCall('setFpsLimit', arguments: 30),
      ]);
    });
  });

  group('events', () {
    late WebviewController controller;

    setUp(() async {
      mockNativeSide();
      controller = WebviewController();
      await controller.initialize();
      expect(eventSink, isNotNull, reason: 'controller must subscribe');
    });

    tearDown(() async {
      await controller.dispose();
    });

    test('urlChanged feeds the url stream', () async {
      final urls = controller.url.first;
      eventSink!.success({'type': 'urlChanged', 'value': 'https://a'});
      expect(await urls, 'https://a');
    });

    test('loadingStateChanged maps indices to LoadingState', () async {
      final states = controller.loadingState.take(2).toList();
      eventSink!.success({'type': 'loadingStateChanged', 'value': 1});
      eventSink!.success({'type': 'loadingStateChanged', 'value': 2});
      expect(await states, [
        LoadingState.loading,
        LoadingState.navigationCompleted,
      ]);
    });

    test('onLoadError maps indices to WebErrorStatus', () async {
      final error = controller.onLoadError.first;
      eventSink!.success({'type': 'onLoadError', 'value': 7});
      expect(await error, WebErrorStatus.timeout);
    });

    test('onLoadError maps unknown future statuses to unknown', () async {
      // A newer WebView2 runtime may report statuses this package does not
      // know yet; they must degrade to `unknown` instead of crashing the
      // event handler with a RangeError.
      final errors = controller.onLoadError.take(2).toList();
      eventSink!.success({'type': 'onLoadError', 'value': 999});
      eventSink!.success({'type': 'onLoadError', 'value': -1});
      expect(await errors, [WebErrorStatus.unknown, WebErrorStatus.unknown]);
    });

    test('historyChanged feeds the historyChanged stream', () async {
      final history = controller.historyChanged.first;
      eventSink!.success({
        'type': 'historyChanged',
        'value': {'canGoBack': true, 'canGoForward': false},
      });
      final value = await history;
      expect(value.canGoBack, isTrue);
      expect(value.canGoForward, isFalse);
    });

    test('downloadEvent feeds the onDownloadEvent stream', () async {
      final download = controller.onDownloadEvent.first;
      eventSink!.success({
        'type': 'downloadEvent',
        'value': {
          'kind': WebviewDownloadEventKind.downloadProgress.index,
          'url': 'https://a/file.zip',
          'resultFilePath': r'C:\Downloads\file.zip',
          'bytesReceived': 10,
          'totalBytesToReceive': 100,
        },
      });
      final value = await download;
      expect(value.kind, WebviewDownloadEventKind.downloadProgress);
      expect(value.url, 'https://a/file.zip');
      expect(value.resultFilePath, r'C:\Downloads\file.zip');
      expect(value.bytesReceived, 10);
      expect(value.totalBytesToReceive, 100);
    });

    test('securityStateChanged and titleChanged feed their streams', () async {
      final security = controller.securityStateChanged.first;
      final title = controller.title.first;
      eventSink!.success({'type': 'securityStateChanged', 'value': '{}'});
      eventSink!.success({'type': 'titleChanged', 'value': 'Hello'});
      expect(await security, '{}');
      expect(await title, 'Hello');
    });

    test('webMessageReceived decodes JSON payloads', () async {
      final message = controller.webMessage.first;
      eventSink!.success({'type': 'webMessageReceived', 'value': '{"a":[1]}'});
      expect(await message, {
        'a': [1],
      });
    });

    test('webMessageReceived emits an error for invalid JSON', () async {
      final message = controller.webMessage.first;
      eventSink!.success({'type': 'webMessageReceived', 'value': '{oops'});
      await expectLater(message, throwsA(isA<FormatException>()));
    });

    test('containsFullScreenElementChanged feeds its stream', () async {
      final fullscreen = controller.containsFullScreenElementChanged.first;
      eventSink!.success({
        'type': 'containsFullScreenElementChanged',
        'value': true,
      });
      expect(await fullscreen, isTrue);
    });

    test('focus events update hasNativeFocus and onFocusChanged', () async {
      expect(controller.hasNativeFocus, isFalse);
      final focus = controller.onFocusChanged.first;
      eventSink!.success({'type': 'focus', 'value': true});
      expect(await focus, isTrue);
      expect(controller.hasNativeFocus, isTrue);
    });

    test('event streams are broadcast: two listeners both receive', () async {
      final first = controller.url.first;
      final second = controller.url.first;
      eventSink!.success({'type': 'urlChanged', 'value': 'https://b'});
      expect(await first, 'https://b');
      expect(await second, 'https://b');
    });
  });

  group('dispose', () {
    test('tears down the native instance and closes the streams', () async {
      mockNativeSide(textureId: 7);
      final controller = WebviewController();
      await controller.initialize();

      final done = controller.url.toList();
      await controller.dispose();

      expect(pluginLog.last, isMethodCall('dispose', arguments: 7));
      expect(await done, isEmpty, reason: 'streams must close on dispose');
    });

    test('is idempotent', () async {
      mockNativeSide();
      final controller = WebviewController();
      await controller.initialize();
      await controller.dispose();
      await controller.dispose();

      expect(pluginLog.where((c) => c.method == 'dispose'), hasLength(1));
    });

    test('completes when called before initialize', () async {
      mockNativeSide();
      final controller = WebviewController();
      await controller.dispose().timeout(const Duration(seconds: 5));
      expect(pluginLog.where((c) => c.method == 'dispose'), isEmpty);
      await expectLater(controller.ready, completes);
    });

    test('completes after a failed initialize', () async {
      mockNativeSide(
        onInitialize: () =>
            throw PlatformException(code: 'webview_creation_failed'),
      );
      final controller = WebviewController();
      await expectLater(
        controller.initialize(),
        throwsA(isA<PlatformException>()),
      );
      await controller.dispose().timeout(const Duration(seconds: 5));
      expect(pluginLog.where((c) => c.method == 'dispose'), isEmpty);
    });

    test('methods become silent no-ops after dispose', () async {
      mockNativeSide();
      final controller = WebviewController();
      await controller.initialize();
      await controller.dispose();
      instanceLog.clear();

      await controller.loadUrl('https://a');
      await controller.reload();
      await controller.setCookie(const WebviewCookie(name: 'a', value: 'b'));
      await controller.deleteCookies('a');
      await controller.setSize(const Size(100, 100));
      expect(await controller.getCookies(), isEmpty);
      expect(instanceLog, isEmpty);
    });
  });

  group('initializeEnvironment', () {
    test('passes all options to the plugin channel', () async {
      mockNativeSide();
      await WebviewController.initializeEnvironment(
        userDataPath: r'C:\data',
        browserExePath: r'C:\edge\msedge.exe',
        additionalArguments: '--disable-features=msSmartScreen',
      );
      expect(
        pluginLog.single,
        isMethodCall(
          'initializeEnvironment',
          arguments: <String, dynamic>{
            'userDataPath': r'C:\data',
            'browserExePath': r'C:\edge\msedge.exe',
            'additionalArguments': '--disable-features=msSmartScreen',
          },
        ),
      );
    });

    test('passes nulls for omitted options', () async {
      mockNativeSide();
      await WebviewController.initializeEnvironment();
      expect(
        pluginLog.single,
        isMethodCall(
          'initializeEnvironment',
          arguments: <String, dynamic>{
            'userDataPath': null,
            'browserExePath': null,
            'additionalArguments': null,
          },
        ),
      );
    });

    test('surfaces a PlatformException when already initialized', () async {
      messenger.setMockMethodCallHandler(_pluginChannel, (call) async {
        throw PlatformException(code: 'already_initialized');
      });
      await expectLater(
        WebviewController.initializeEnvironment(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'already_initialized',
          ),
        ),
      );
    });
  });

  group('releaseFocus', () {
    test('invokes reclaimFocus on the plugin channel', () async {
      mockNativeSide();
      await WebviewController.releaseFocus();
      expect(pluginLog.last, isMethodCall('reclaimFocus', arguments: null));
    });

    test('swallows errors when the plugin is unavailable', () async {
      messenger.setMockMethodCallHandler(_pluginChannel, null);
      await expectLater(WebviewController.releaseFocus(), completes);
    });
  });

  group('getWebViewVersion', () {
    test('returns the reported version', () async {
      messenger.setMockMethodCallHandler(
        _pluginChannel,
        (call) async => '110.0.1587.57',
      );
      expect(await WebviewController.getWebViewVersion(), '110.0.1587.57');
    });

    test('returns null when no runtime is installed', () async {
      messenger.setMockMethodCallHandler(_pluginChannel, (call) async => null);
      expect(await WebviewController.getWebViewVersion(), isNull);
    });
  });

  group('Webview widget', () {
    // testWidgets bodies run in a FakeAsync zone where awaiting platform
    // channel round trips can hang (see the asyncHandlers note on
    // TestDefaultBinaryMessenger): the event channel teardown hops through
    // the root zone, after which pending channel futures are no longer
    // driven by the fake microtask pump. Wrapping initialize/dispose in
    // tester.runAsync runs them under real asynchrony. Package users writing
    // widget tests against a mocked WebviewController need the same pattern.
    Future<WebviewController> createInitializedController(
      WidgetTester tester,
    ) async {
      mockNativeSide();
      final controller = WebviewController();
      await tester.runAsync(controller.initialize);
      instanceLog.clear();
      return controller;
    }

    Future<void> unmountAndDispose(
      WidgetTester tester,
      WebviewController controller,
    ) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(controller.dispose);
    }

    testWidgets('reports the surface size once the controller is ready', (
      tester,
    ) async {
      final controller = await createInitializedController(tester);

      await tester.pumpWidget(Webview(controller));
      await tester.pump();

      final setSize = instanceLog.where((c) => c.method == 'setSize').toList();
      expect(setSize, hasLength(1));
      final args = setSize.single.arguments as List<dynamic>;
      expect(args[0], 800.0);
      expect(args[1], 600.0);
      expect(args[2], tester.view.devicePixelRatio);

      await unmountAndDispose(tester, controller);
    });

    testWidgets('honors a custom scaleFactor when reporting the size', (
      tester,
    ) async {
      final controller = await createInitializedController(tester);

      await tester.pumpWidget(Webview(controller, scaleFactor: 1.0));
      await tester.pump();

      final setSize = instanceLog.where((c) => c.method == 'setSize').single;
      expect((setSize.arguments as List<dynamic>)[2], 1.0);

      await unmountAndDispose(tester, controller);
    });

    testWidgets('renders the controller texture', (tester) async {
      final controller = await createInitializedController(tester);

      await tester.pumpWidget(Webview(controller));
      final texture = tester.widget<Texture>(find.byType(Texture));
      expect(texture.textureId, 1);
      expect(texture.filterQuality, FilterQuality.none);

      await unmountAndDispose(tester, controller);
    });

    testWidgets('forwards mouse presses as cursor position plus button state', (
      tester,
    ) async {
      final controller = await createInitializedController(tester);
      await tester.pumpWidget(Webview(controller));

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await gesture.down(const Offset(100, 50));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final calls = instanceLog
          .where(
            (c) => c.method == 'setCursorPos' || c.method == 'setPointerButton',
          )
          .toList();
      expect(calls, [
        isMethodCall('setCursorPos', arguments: [100.0, 50.0]),
        isMethodCall(
          'setPointerButton',
          arguments: {'button': PointerButton.primary.index, 'isDown': true},
        ),
        isMethodCall(
          'setPointerButton',
          arguments: {'button': PointerButton.primary.index, 'isDown': false},
        ),
      ]);

      await unmountAndDispose(tester, controller);
    });

    testWidgets('forwards secondary mouse button presses', (tester) async {
      final controller = await createInitializedController(tester);
      await tester.pumpWidget(Webview(controller));

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.down(const Offset(10, 10));
      await gesture.up();
      await tester.pump();

      expect(
        instanceLog.where((c) => c.method == 'setPointerButton').first,
        isMethodCall(
          'setPointerButton',
          arguments: {'button': PointerButton.secondary.index, 'isDown': true},
        ),
      );

      await unmountAndDispose(tester, controller);
    });

    testWidgets('forwards mouse movement as cursor updates', (tester) async {
      final controller = await createInitializedController(tester);
      await tester.pumpWidget(Webview(controller));

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await gesture.down(const Offset(20, 20));
      await gesture.moveTo(const Offset(40, 60));
      await gesture.up();
      await tester.pump();

      expect(
        instanceLog.where((c) => c.method == 'setCursorPos'),
        contains(isMethodCall('setCursorPos', arguments: [40.0, 60.0])),
      );

      await unmountAndDispose(tester, controller);
    });

    testWidgets('forwards scroll wheel signals with inverted deltas', (
      tester,
    ) async {
      final controller = await createInitializedController(tester);
      await tester.pumpWidget(Webview(controller));

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(100, 100)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(8, 24)));
      await tester.pump();

      expect(
        instanceLog.where((c) => c.method == 'setScrollDelta').single,
        isMethodCall('setScrollDelta', arguments: [-8.0, -24.0]),
      );

      await unmountAndDispose(tester, controller);
    });

    testWidgets('forwards trackpad panning along the dominant axis', (
      tester,
    ) async {
      final controller = await createInitializedController(tester);
      await tester.pumpWidget(Webview(controller));

      final pointer = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(
        pointer.panZoomStart(const Offset(100, 100)),
      );
      // Vertical-dominant pan: only the y delta is forwarded (not inverted).
      await tester.sendEventToBinding(
        pointer.panZoomUpdate(const Offset(100, 100), pan: const Offset(2, 30)),
      );
      // Horizontal-dominant pan: only the x delta is forwarded, inverted.
      await tester.sendEventToBinding(
        pointer.panZoomUpdate(
          const Offset(100, 100),
          pan: const Offset(42, 35),
        ),
      );
      await tester.sendEventToBinding(pointer.panZoomEnd());
      await tester.pump();

      expect(instanceLog.where((c) => c.method == 'setScrollDelta'), [
        isMethodCall('setScrollDelta', arguments: [0.0, 30.0]),
        isMethodCall('setScrollDelta', arguments: [-40.0, 0.0]),
      ]);

      await unmountAndDispose(tester, controller);
    });

    testWidgets('forwards touch input as pointer updates', (tester) async {
      final controller = await createInitializedController(tester);
      await tester.pumpWidget(Webview(controller));

      final gesture = await tester.createGesture();
      await gesture.down(const Offset(30, 40));
      await gesture.moveTo(const Offset(50, 60));
      await gesture.up();
      await tester.pump();

      final updates = instanceLog
          .where((c) => c.method == 'setPointerUpdate')
          .map((c) => c.arguments as List<dynamic>)
          .toList();
      expect(updates, hasLength(3));
      expect(updates[0][1], WebviewPointerEventKind.down.index);
      expect(updates[0][2], 30.0);
      expect(updates[0][3], 40.0);
      expect(updates[1][1], WebviewPointerEventKind.update.index);
      expect(updates[1][2], 50.0);
      expect(updates[1][3], 60.0);
      expect(updates[2][1], WebviewPointerEventKind.up.index);
      // Touch input must not produce mouse button events.
      expect(instanceLog.where((c) => c.method == 'setPointerButton'), isEmpty);

      await unmountAndDispose(tester, controller);
    });

    testWidgets('applies cursorChanged events to the MouseRegion', (
      tester,
    ) async {
      final controller = await createInitializedController(tester);
      await tester.pumpWidget(Webview(controller));

      expect(
        tester.widget<MouseRegion>(find.byType(MouseRegion).last).cursor,
        SystemMouseCursors.basic,
      );

      eventSink!.success({'type': 'cursorChanged', 'value': 'text'});
      // The event crosses real-async zones (the channel was subscribed inside
      // runAsync), so settle real microtasks before pumping the fake ones.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(
        tester.widget<MouseRegion>(find.byType(MouseRegion).last).cursor,
        SystemMouseCursors.text,
      );

      await unmountAndDispose(tester, controller);
    });

    testWidgets('permissionRequested round trip', (tester) async {
      final controller = await createInitializedController(tester);

      var decision = WebviewPermissionDecision.allow;
      WebviewPermissionKind? receivedKind;
      String? receivedUrl;
      bool? receivedUserInitiated;
      await tester.pumpWidget(
        Webview(
          controller,
          permissionRequested: (url, kind, isUserInitiated) {
            receivedUrl = url;
            receivedKind = kind;
            receivedUserInitiated = isUserInitiated;
            return decision;
          },
        ),
      );

      Future<Object?> requestPermission() {
        return tester.runAsync<Object?>(() async {
          ByteData? reply;
          await messenger.handlePlatformMessage(
            'io.jns.webview.win/1',
            _codec.encodeMethodCall(
              const MethodCall('permissionRequested', {
                'url': 'https://a',
                'permissionKind': 2, // camera
                'isUserInitiated': true,
              }),
            ),
            (data) => reply = data,
          );
          return _codec.decodeEnvelope(reply!);
        });
      }

      expect(await requestPermission(), isTrue);
      expect(receivedUrl, 'https://a');
      expect(receivedKind, WebviewPermissionKind.camera);
      expect(receivedUserInitiated, isTrue);

      decision = WebviewPermissionDecision.deny;
      expect(await requestPermission(), isFalse);

      decision = WebviewPermissionDecision.none;
      expect(await requestPermission(), isNull);

      await unmountAndDispose(tester, controller);
    });

    testWidgets('permissionRequested defers when no delegate is set', (
      tester,
    ) async {
      final controller = await createInitializedController(tester);
      await tester.pumpWidget(Webview(controller));

      final reply = await tester.runAsync(() async {
        ByteData? data;
        await messenger.handlePlatformMessage(
          'io.jns.webview.win/1',
          _codec.encodeMethodCall(
            const MethodCall('permissionRequested', {
              'url': 'https://a',
              'permissionKind': 1,
              'isUserInitiated': false,
            }),
          ),
          (d) => data = d,
        );
        return _codec.decodeEnvelope(data!);
      });
      expect(reply, isNull);

      await unmountAndDispose(tester, controller);
    });

    testWidgets('clicking Flutter UI while the webview has native focus '
        'returns focus to Flutter', (tester) async {
      final controller = await createInitializedController(tester);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              SizedBox(width: 300, height: 300, child: Webview(controller)),
              Container(
                width: 300,
                height: 300,
                color: const Color(0xFF000000),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      // Give the webview native focus (as WebView2 reports after a click).
      eventSink!.success({'type': 'focus', 'value': true});
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(controller.hasNativeFocus, isTrue);

      // The Column centers its 300px-wide children on the 800px test
      // surface, so the webview occupies x 250..550, y 0..300.
      // A press inside the webview is claimed and must NOT reclaim focus.
      pluginLog.clear();
      await tester.tapAt(const Offset(400, 150));
      await tester.pump();
      expect(pluginLog.where((c) => c.method == 'reclaimFocus'), isEmpty);

      // A press outside every webview must hand focus back to Flutter.
      await tester.tapAt(const Offset(400, 450));
      await tester.pump();
      expect(pluginLog.where((c) => c.method == 'reclaimFocus'), hasLength(1));

      await unmountAndDispose(tester, controller);
    });

    testWidgets('does not reclaim focus when no webview has native focus', (
      tester,
    ) async {
      final controller = await createInitializedController(tester);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              SizedBox(width: 300, height: 300, child: Webview(controller)),
              Container(
                width: 300,
                height: 300,
                color: const Color(0xFF000000),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      pluginLog.clear();
      await tester.tapAt(const Offset(150, 450));
      await tester.pump();
      expect(pluginLog.where((c) => c.method == 'reclaimFocus'), isEmpty);

      await unmountAndDispose(tester, controller);
    });

    testWidgets('focusing a Flutter text input while the webview has native '
        'focus returns focus to Flutter', (tester) async {
      final controller = await createInitializedController(tester);
      final textFieldFocus = FocusNode();
      addTearDown(textFieldFocus.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(width: 300, height: 300, child: Webview(controller)),
                TextField(focusNode: textFieldFocus),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Focusing the text input while no webview holds native focus must not
      // trigger a handover.
      pluginLog.clear();
      textFieldFocus.requestFocus();
      await tester.pump();
      expect(pluginLog.where((c) => c.method == 'reclaimFocus'), isEmpty);
      textFieldFocus.unfocus();
      await tester.pump();

      // Give the webview native focus (as WebView2 reports after a click).
      eventSink!.success({'type': 'focus', 'value': true});
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(controller.hasNativeFocus, isTrue);

      // A text input gaining Flutter focus - e.g. an autofocused TextField in
      // a programmatically opened dialog - must hand native focus back even
      // though no pointer press occurred.
      pluginLog.clear();
      textFieldFocus.requestFocus();
      await tester.pump();
      expect(pluginLog.where((c) => c.method == 'reclaimFocus'), hasLength(1));

      await unmountAndDispose(tester, controller);
    });

    testWidgets('webview gaining native focus while a text input is focused '
        'hands focus straight back', (tester) async {
      final controller = await createInitializedController(tester);
      final textFieldFocus = FocusNode();
      addTearDown(textFieldFocus.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(width: 300, height: 300, child: Webview(controller)),
                TextField(focusNode: textFieldFocus),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // The text input owns Flutter focus FIRST...
      textFieldFocus.requestFocus();
      await tester.pump();
      expect(textFieldFocus.hasPrimaryFocus, isTrue);

      // ...and only then does the webview report a native focus grab (a
      // programmatic focus(), page script, or a stale recovery path firing
      // late). The grab must be reverted: this is the event ordering the
      // Flutter-focus listener alone cannot see, because no Flutter focus
      // change happens after the grab.
      pluginLog.clear();
      eventSink!.success({'type': 'focus', 'value': true});
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(pluginLog.where((c) => c.method == 'reclaimFocus'), hasLength(1));

      await unmountAndDispose(tester, controller);
    });

    testWidgets('webview gaining native focus while a wrapper Focus node is '
        'focused is left alone', (tester) async {
      final controller = await createInitializedController(tester);
      final wrapperFocus = FocusNode();
      addTearDown(wrapperFocus.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(width: 300, height: 300, child: Webview(controller)),
                Focus(focusNode: wrapperFocus, child: const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Embedding packages park Flutter focus on a wrapper node and then
      // hand native focus to the page (the click-into-the-editor flow).
      // That grab is legitimate and must not be reverted.
      wrapperFocus.requestFocus();
      await tester.pump();

      pluginLog.clear();
      eventSink!.success({'type': 'focus', 'value': true});
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(pluginLog.where((c) => c.method == 'reclaimFocus'), isEmpty);

      await unmountAndDispose(tester, controller);
    });

    testWidgets('focusing a non-text-input node does not release native '
        'focus', (tester) async {
      final controller = await createInitializedController(tester);
      final wrapperFocus = FocusNode();
      addTearDown(wrapperFocus.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(width: 300, height: 300, child: Webview(controller)),
                Focus(focusNode: wrapperFocus, child: const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      eventSink!.success({'type': 'focus', 'value': true});
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(controller.hasNativeFocus, isTrue);

      // Packages embedding the webview park Flutter focus on a wrapper Focus
      // node when the user clicks into web content; that must not be treated
      // as Flutter UI demanding the keyboard.
      pluginLog.clear();
      wrapperFocus.requestFocus();
      await tester.pump();
      expect(pluginLog.where((c) => c.method == 'reclaimFocus'), isEmpty);

      await unmountAndDispose(tester, controller);
    });
  });

  group('native enum contracts', () {
    // These indices are the wire format shared with the C++ side (webview.h
    // and COREWEBVIEW2_WEB_ERROR_STATUS). Reordering any of these enums is a
    // breaking change to the platform channel protocol.
    test('LoadingState order', () {
      expect(LoadingState.values, const [
        LoadingState.none,
        LoadingState.loading,
        LoadingState.navigationCompleted,
      ]);
    });

    test('PointerButton order', () {
      expect(PointerButton.values, const [
        PointerButton.none,
        PointerButton.primary,
        PointerButton.secondary,
        PointerButton.tertiary,
      ]);
    });

    test('WebviewPointerEventKind order', () {
      expect(WebviewPointerEventKind.values, const [
        WebviewPointerEventKind.activate,
        WebviewPointerEventKind.down,
        WebviewPointerEventKind.enter,
        WebviewPointerEventKind.leave,
        WebviewPointerEventKind.up,
        WebviewPointerEventKind.update,
      ]);
    });

    test('WebviewPermissionKind order', () {
      expect(WebviewPermissionKind.values, const [
        WebviewPermissionKind.unknown,
        WebviewPermissionKind.microphone,
        WebviewPermissionKind.camera,
        WebviewPermissionKind.geoLocation,
        WebviewPermissionKind.notifications,
        WebviewPermissionKind.otherSensors,
        WebviewPermissionKind.clipboardRead,
      ]);
    });

    test('WebviewPopupWindowPolicy order', () {
      expect(WebviewPopupWindowPolicy.values, const [
        WebviewPopupWindowPolicy.allow,
        WebviewPopupWindowPolicy.deny,
        WebviewPopupWindowPolicy.sameWindow,
      ]);
    });

    test('WebviewHostResourceAccessKind order', () {
      expect(WebviewHostResourceAccessKind.values, const [
        WebviewHostResourceAccessKind.deny,
        WebviewHostResourceAccessKind.allow,
        WebviewHostResourceAccessKind.denyCors,
      ]);
    });

    test('WebviewCookieSameSite order', () {
      expect(WebviewCookieSameSite.values, const [
        WebviewCookieSameSite.none,
        WebviewCookieSameSite.lax,
        WebviewCookieSameSite.strict,
      ]);
    });

    test('WebErrorStatus matches COREWEBVIEW2_WEB_ERROR_STATUS', () {
      expect(WebErrorStatus.values, hasLength(19));
      expect(WebErrorStatus.unknown.index, 0);
      expect(WebErrorStatus.certificateCommonNameIsIncorrect.index, 1);
      expect(WebErrorStatus.certificateExpired.index, 2);
      expect(WebErrorStatus.clientCertificateContainsErrors.index, 3);
      expect(WebErrorStatus.certificateRevoked.index, 4);
      expect(WebErrorStatus.certificateIsInvalid.index, 5);
      expect(WebErrorStatus.serverUnreachable.index, 6);
      expect(WebErrorStatus.timeout.index, 7);
      expect(WebErrorStatus.errorHttpInvalidServerResponse.index, 8);
      expect(WebErrorStatus.connectionAborted.index, 9);
      expect(WebErrorStatus.connectionReset.index, 10);
      expect(WebErrorStatus.disconnected.index, 11);
      expect(WebErrorStatus.cannotConnect.index, 12);
      expect(WebErrorStatus.hostNameNotResolved.index, 13);
      expect(WebErrorStatus.operationCanceled.index, 14);
      expect(WebErrorStatus.redirectFailed.index, 15);
      expect(WebErrorStatus.unexpectedError.index, 16);
      expect(WebErrorStatus.validAuthenticationCredentialsRequired.index, 17);
      expect(WebErrorStatus.validProxyAuthenticationRequired.index, 18);
    });
  });
}
