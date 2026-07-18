// A fake native side for webview_flutter_windows tests.
//
// Copy this file into your project (e.g. test/support/webview_channel_fake.dart).
// It mirrors the package's real channel contract:
//   - plugin channel  io.jns.webview.win           (initialize/dispose/...)
//   - method channel  io.jns.webview.win/<id>      (all controller methods)
//   - event channel   io.jns.webview.win/<id>/events (native -> Dart events)

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

/// Installs mock handlers for every channel `webview_flutter_windows` uses,
/// records outgoing calls, and lets tests inject native events.
class WebviewChannelFake {
  /// Creates a fake native side; [textureId] is what `initialize` reports.
  WebviewChannelFake({this.textureId = 1});

  /// The texture id returned from `initialize`.
  final int textureId;

  /// Calls received on the plugin channel (`initialize`, `dispose`, ...).
  final List<MethodCall> pluginCalls = <MethodCall>[];

  /// Calls received on the per-instance channel (`loadUrl`, ...).
  final List<MethodCall> instanceCalls = <MethodCall>[];

  /// Override the result of `initialize` (throw to simulate failure).
  Object? Function()? onInitialize;

  /// Override per-method results for the instance channel; return values are
  /// sent back to the controller (throw a [PlatformException] to simulate a
  /// native error). Return null for void methods.
  Object? Function(MethodCall call)? onInstanceCall;

  /// The version string reported by `getWebViewVersion` (null simulates a
  /// missing WebView2 Runtime).
  String? webViewVersion = '999.0.0.0';

  MockStreamHandlerEventSink? _eventSink;

  static const MethodChannel _pluginChannel = MethodChannel(
    'io.jns.webview.win',
  );

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  MethodChannel get _instanceChannel =>
      MethodChannel('io.jns.webview.win/$textureId');

  /// Installs all mock handlers. Call before creating/initializing any
  /// [WebviewController].
  void install() {
    _messenger.setMockMethodCallHandler(_pluginChannel, (call) async {
      pluginCalls.add(call);
      switch (call.method) {
        case 'initialize':
          final override = onInitialize;
          if (override != null) {
            return override();
          }
          // The controller requires exactly this shape.
          return <String, dynamic>{'textureId': textureId};
        case 'getWebViewVersion':
          return webViewVersion;
        default:
          return null;
      }
    });

    _messenger.setMockMethodCallHandler(_instanceChannel, (call) async {
      instanceCalls.add(call);
      return onInstanceCall?.call(call);
    });

    _messenger.setMockStreamHandler(
      EventChannel('io.jns.webview.win/$textureId/events'),
      // Block bodies on purpose: the mock encodes the callback's runtime
      // return value into the listen/cancel reply envelope, and an arrow
      // body would leak the (unencodable) assignment value.
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          _eventSink = events;
        },
        onCancel: (arguments) {
          _eventSink = null;
        },
      ),
    );
  }

  /// Removes every handler installed by [install]. Call in `tearDown`.
  void uninstall() {
    _messenger.setMockMethodCallHandler(_pluginChannel, null);
    _messenger.setMockMethodCallHandler(_instanceChannel, null);
    _eventSink = null;
  }

  /// Injects a raw native event (`{'type': ..., 'value': ...}`).
  ///
  /// Fails the test if no controller is listening yet: initialize the
  /// controller first, and in `testWidgets` remember `tester.runAsync`.
  void emitEvent(Map<String, dynamic> event) {
    final sink = _eventSink;
    if (sink == null) {
      fail(
        'No event listener attached. Initialize a WebviewController before '
        'emitting events (in testWidgets, inside tester.runAsync).',
      );
    }
    sink.success(event);
  }

  /// Emits a navigation URL change.
  void emitUrlChanged(String url) =>
      emitEvent(<String, dynamic>{'type': 'urlChanged', 'value': url});

  /// Emits a loading-state change.
  void emitLoadingState(LoadingState state) => emitEvent(<String, dynamic>{
    'type': 'loadingStateChanged',
    'value': state.index,
  });

  /// Emits a navigation error.
  void emitLoadError(WebErrorStatus status) => emitEvent(<String, dynamic>{
    'type': 'onLoadError',
    'value': status.index,
  });

  /// Emits a document title change.
  void emitTitleChanged(String title) =>
      emitEvent(<String, dynamic>{'type': 'titleChanged', 'value': title});

  /// Emits a history (back/forward availability) change.
  void emitHistoryChanged({
    required bool canGoBack,
    required bool canGoForward,
  }) => emitEvent(<String, dynamic>{
    'type': 'historyChanged',
    'value': <String, dynamic>{
      'canGoBack': canGoBack,
      'canGoForward': canGoForward,
    },
  });

  /// Emits a message from the page. [json] must be a JSON-encoded string,
  /// exactly as the native side forwards it (it arrives decoded on
  /// `controller.webMessage`).
  void emitWebMessage(String json) =>
      emitEvent(<String, dynamic>{'type': 'webMessageReceived', 'value': json});

  /// Emits a native keyboard-focus change.
  void emitFocusChanged({required bool focused}) =>
      emitEvent(<String, dynamic>{'type': 'focus', 'value': focused});

  /// Emits a full-screen element presence change.
  void emitContainsFullScreenElementChanged({required bool contains}) =>
      emitEvent(<String, dynamic>{
        'type': 'containsFullScreenElementChanged',
        'value': contains,
      });
}
