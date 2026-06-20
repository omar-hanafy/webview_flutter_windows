import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter_windows/src/cursor.dart';
import 'package:webview_flutter_windows/src/enums.dart';

/// A snapshot of the webview's navigation history state.
class HistoryChanged {
  /// Whether the webview can navigate back.
  final bool canGoBack;

  /// Whether the webview can navigate forward.
  final bool canGoForward;

  /// Creates a history snapshot.
  const HistoryChanged(this.canGoBack, this.canGoForward);
}

/// A download lifecycle notification emitted on
/// [WebviewController.onDownloadEvent].
class WebviewDownloadEvent {
  /// The kind of download event.
  final WebviewDownloadEventKind kind;

  /// The URL the download originates from.
  final String url;

  /// The target file path of the download.
  final String resultFilePath;

  /// The number of bytes received so far.
  final int bytesReceived;

  /// The expected total number of bytes, or 0 if unknown.
  final int totalBytesToReceive;

  /// Creates a download event.
  const WebviewDownloadEvent(
    this.kind,
    this.url,
    this.resultFilePath,
    this.bytesReceived,
    this.totalBytesToReceive,
  );
}

/// An HTTP cookie, as managed by the WebView2 cookie store.
///
/// Returned by [WebviewController.getCookies] and accepted by
/// [WebviewController.setCookie].
class WebviewCookie {
  /// The cookie name.
  final String name;

  /// The cookie value.
  final String value;

  /// The host the cookie belongs to. An empty domain on [setCookie] scopes
  /// the cookie to the document's host.
  final String domain;

  /// The URL path the cookie applies to.
  final String path;

  /// The expiration time, or `null` for a session cookie.
  final DateTime? expires;

  /// Whether the cookie is only sent over HTTPS.
  final bool isSecure;

  /// Whether the cookie is inaccessible to JavaScript.
  final bool isHttpOnly;

  /// The SameSite policy of the cookie.
  final WebviewCookieSameSite sameSite;

  /// Whether this is a session cookie (no expiration time).
  bool get isSession => expires == null;

  /// Creates a cookie. [domain] and [path] follow the browser defaults when
  /// omitted; omit [expires] for a session cookie.
  const WebviewCookie({
    required this.name,
    required this.value,
    this.domain = '',
    this.path = '/',
    this.expires,
    this.isSecure = false,
    this.isHttpOnly = false,
    this.sameSite = WebviewCookieSameSite.lax,
  });

  WebviewCookie._fromNative(Map<dynamic, dynamic> map)
    : name = map['name'] as String,
      value = map['value'] as String,
      domain = map['domain'] as String,
      path = map['path'] as String,
      expires = (map['expires'] as double) < 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              ((map['expires'] as double) * 1000).round(),
              isUtc: true,
            ),
      isSecure = map['isSecure'] as bool,
      isHttpOnly = map['isHttpOnly'] as bool,
      sameSite = _sameSiteFromNative(map['sameSite'] as int);

  // A newer WebView2 runtime could report a SameSite kind this enum does not
  // know; degrade to the browser default instead of throwing a RangeError.
  static WebviewCookieSameSite _sameSiteFromNative(int index) =>
      index >= 0 && index < WebviewCookieSameSite.values.length
      ? WebviewCookieSameSite.values[index]
      : WebviewCookieSameSite.lax;

  Map<String, dynamic> _toNative() => <String, dynamic>{
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    'expires': expires == null
        ? -1.0
        : expires!.millisecondsSinceEpoch / 1000.0,
    'isSecure': isSecure,
    'isHttpOnly': isHttpOnly,
    'sameSite': sameSite.index,
  };
}

/// Invoked when the web content requests a browser permission (camera,
/// microphone, geolocation etc.).
///
/// Return a [WebviewPermissionDecision] to allow or deny the request, or
/// [WebviewPermissionDecision.none] to defer to the WebView2 default
/// behavior.
typedef PermissionRequestedDelegate =
    FutureOr<WebviewPermissionDecision> Function(
      String url,
      WebviewPermissionKind permissionKind,
      bool isUserInitiated,
    );

/// Identifies a script registered with
/// [WebviewController.addScriptToExecuteOnDocumentCreated].
typedef ScriptID = String;

PointerButton _getButton(int value) {
  switch (value) {
    case kPrimaryMouseButton:
      return PointerButton.primary;
    case kSecondaryMouseButton:
      return PointerButton.secondary;
    case kTertiaryButton:
      return PointerButton.tertiary;
    default:
      return PointerButton.none;
  }
}

const String _pluginChannelPrefix = 'io.jns.webview.win';
const MethodChannel _pluginChannel = MethodChannel(_pluginChannelPrefix);

/// The state of a [WebviewController], exposed through
/// [WebviewController.value].
class WebviewValue {
  /// Creates a webview state.
  const WebviewValue({required this.isInitialized});

  /// Creates the initial, uninitialized state.
  const WebviewValue.uninitialized() : this(isInitialized: false);

  /// Whether [WebviewController.initialize] has completed successfully.
  final bool isInitialized;

  /// Returns a copy of this value with the given fields replaced.
  WebviewValue copyWith({bool? isInitialized}) {
    return WebviewValue(isInitialized: isInitialized ?? this.isInitialized);
  }
}

/// Controls a native WebView2 instance and exposes its events as broadcast
/// streams.
///
/// The typical lifecycle is:
///
/// ```dart
/// final controller = WebviewController();
/// await controller.initialize();
/// await controller.loadUrl('https://flutter.dev');
/// // ... embed it with a [Webview] widget ...
/// await controller.dispose();
/// ```
///
/// All event streams are broadcast streams: they support multiple listeners
/// and drop events that are emitted while nobody listens.
class WebviewController extends ValueNotifier<WebviewValue> {
  /// Explicitly configures the underlying WebView environment
  /// using an optional [browserExePath], an optional [userDataPath]
  /// and optional Chromium command line arguments [additionalArguments].
  ///
  /// The environment is shared between all WebviewController instances. Its
  /// lifecycle is reference counted: it is created with the first controller
  /// and released when the last controller is disposed, so this method can
  /// be called again - with a different configuration - once every
  /// controller has been disposed.
  ///
  /// Throws [PlatformException] if any controller is currently alive.
  static Future<void> initializeEnvironment({
    String? userDataPath,
    String? browserExePath,
    String? additionalArguments,
  }) async {
    return _pluginChannel
        .invokeMethod('initializeEnvironment', <String, dynamic>{
          'userDataPath': userDataPath,
          'browserExePath': browserExePath,
          'additionalArguments': additionalArguments,
        });
  }

  /// Returns the browser version info including channel name if it is not the
  /// stable WebView2 Runtime.
  ///
  /// Returns `null` if the WebView2 Runtime is not installed.
  static Future<String?> getWebViewVersion() async {
    return _pluginChannel.invokeMethod<String>('getWebViewVersion');
  }

  /// Returns native (Win32) keyboard focus to the Flutter view, restoring
  /// Flutter's keyboard event handling (shortcuts, text fields, etc.).
  ///
  /// This is invoked automatically whenever the user clicks outside of any
  /// [Webview] while a webview holds native focus. Calling it manually is
  /// only needed when moving focus away from the webview programmatically.
  static Future<void> releaseFocus() async {
    try {
      await _pluginChannel.invokeMethod('reclaimFocus');
    } on Exception {
      // The plugin is unavailable (e.g. running on a non-Windows host or in
      // a widget test); there is no native focus to release in that case.
    }
  }

  /// Creates an uninitialized controller. Call [initialize] before use.
  WebviewController() : super(const WebviewValue.uninitialized());

  Completer<void>? _creatingCompleter;
  final Completer<void> _readyCompleter = Completer<void>();
  int _textureId = 0;
  bool _isDisposed = false;

  /// A future that completes once the controller has been initialized.
  ///
  /// It also completes when the controller is disposed before ever being
  /// initialized, so awaiting it can never hang; check [value] afterwards.
  Future<void> get ready => _readyCompleter.future;

  PermissionRequestedDelegate? _permissionRequested;

  MethodChannel? _methodChannel;
  StreamSubscription<dynamic>? _eventStreamSubscription;

  /// The per-instance method channel, available only after initialization.
  MethodChannel get _channel {
    final channel = _methodChannel;
    if (channel == null) {
      throw StateError(
        'WebviewController is not initialized. Call initialize() first.',
      );
    }
    return channel;
  }

  final StreamController<String> _urlStreamController =
      StreamController<String>.broadcast();

  /// A stream reflecting the current URL.
  Stream<String> get url => _urlStreamController.stream;

  final StreamController<LoadingState> _loadingStateStreamController =
      StreamController<LoadingState>.broadcast();

  /// A stream reflecting the current loading state.
  Stream<LoadingState> get loadingState => _loadingStateStreamController.stream;

  final StreamController<WebviewDownloadEvent> _downloadEventStreamController =
      StreamController<WebviewDownloadEvent>.broadcast();

  /// A stream of download lifecycle events (started, progress, completed).
  Stream<WebviewDownloadEvent> get onDownloadEvent =>
      _downloadEventStreamController.stream;

  final StreamController<WebErrorStatus> _onLoadErrorStreamController =
      StreamController<WebErrorStatus>.broadcast();

  /// A stream reflecting the navigation error when navigation completed with
  /// an error.
  Stream<WebErrorStatus> get onLoadError => _onLoadErrorStreamController.stream;

  final StreamController<HistoryChanged> _historyChangedStreamController =
      StreamController<HistoryChanged>.broadcast();

  /// A stream reflecting the current history state.
  Stream<HistoryChanged> get historyChanged =>
      _historyChangedStreamController.stream;

  final StreamController<String> _securityStateChangedStreamController =
      StreamController<String>.broadcast();

  /// A stream reflecting the current security state as a JSON string
  /// (Chrome DevTools Protocol `Security.securityStateChanged` payload).
  Stream<String> get securityStateChanged =>
      _securityStateChangedStreamController.stream;

  final StreamController<String> _titleStreamController =
      StreamController<String>.broadcast();

  /// A stream reflecting the current document title.
  Stream<String> get title => _titleStreamController.stream;

  final StreamController<SystemMouseCursor> _cursorStreamController =
      StreamController<SystemMouseCursor>.broadcast();

  /// A stream reflecting the current cursor style.
  Stream<SystemMouseCursor> get _cursor => _cursorStreamController.stream;

  final StreamController<dynamic> _webMessageStreamController =
      StreamController<dynamic>.broadcast();

  /// A stream of JSON-decoded messages posted by the web content through
  /// `window.chrome.webview.postMessage`.
  ///
  /// Emits an error event if a message is not valid JSON.
  Stream<dynamic> get webMessage => _webMessageStreamController.stream;

  final StreamController<bool>
  _containsFullScreenElementChangedStreamController =
      StreamController<bool>.broadcast();

  /// A stream reflecting whether the document currently contains full-screen
  /// elements.
  Stream<bool> get containsFullScreenElementChanged =>
      _containsFullScreenElementChangedStreamController.stream;

  final StreamController<bool> _focusChangedStreamController =
      StreamController<bool>.broadcast();

  /// A stream reflecting whether the underlying WebView2 control currently
  /// holds native (Win32) keyboard focus.
  Stream<bool> get onFocusChanged => _focusChangedStreamController.stream;

  bool _hasNativeFocus = false;

  /// Whether the underlying WebView2 control currently holds native (Win32)
  /// keyboard focus.
  bool get hasNativeFocus => _hasNativeFocus;

  /// Initializes the underlying platform webview.
  ///
  /// Safe to call multiple times: concurrent calls join the in-flight
  /// initialization and calling it on an initialized controller is a no-op.
  /// If initialization fails, the returned future completes with the error
  /// (typically a [PlatformException]) and a later retry is allowed.
  ///
  /// Throws a [StateError] if the controller has been disposed.
  Future<void> initialize() {
    if (_isDisposed) {
      throw StateError('WebviewController.initialize() called after dispose.');
    }
    if (value.isInitialized) {
      return Future<void>.value();
    }
    // Join an in-flight initialization instead of racing a second native
    // instance into existence.
    final inFlight = _creatingCompleter;
    if (inFlight != null) {
      return inFlight.future;
    }
    final completer = _creatingCompleter = Completer<void>();
    () async {
      try {
        final reply = await _pluginChannel.invokeMapMethod<String, dynamic>(
          'initialize',
        );

        _textureId = reply!['textureId'] as int;
        final methodChannel = MethodChannel(
          '$_pluginChannelPrefix/$_textureId',
        );
        final eventChannel = EventChannel(
          '$_pluginChannelPrefix/$_textureId/events',
        );
        _methodChannel = methodChannel;
        _eventStreamSubscription = eventChannel.receiveBroadcastStream().listen(
          _handleEvent,
        );
        methodChannel.setMethodCallHandler(_handleMethodCall);

        value = value.copyWith(isInitialized: true);
        completer.complete();
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.complete();
        }
      } catch (error, stackTrace) {
        // Allow a later retry; the failed attempt must not stay armed as the
        // in-flight initialization forever.
        _creatingCompleter = null;
        completer.completeError(error, stackTrace);
      }
    }();
    return completer.future;
  }

  void _handleEvent(dynamic event) {
    final map = event as Map<dynamic, dynamic>;
    switch (map['type']) {
      case 'urlChanged':
        _urlStreamController.add(map['value']);
        break;
      case 'onLoadError':
        // The native side forwards COREWEBVIEW2_WEB_ERROR_STATUS verbatim and
        // the WebView2 runtime versions independently of this package, so a
        // newer runtime may report a status this enum does not know yet.
        final index = map['value'] as int;
        final value = index >= 0 && index < WebErrorStatus.values.length
            ? WebErrorStatus.values[index]
            : WebErrorStatus.unknown;
        _onLoadErrorStreamController.add(value);
        break;
      case 'loadingStateChanged':
        final value = LoadingState.values[map['value']];
        _loadingStateStreamController.add(value);
        break;
      case 'downloadEvent':
        final value = WebviewDownloadEvent(
          WebviewDownloadEventKind.values[map['value']['kind']],
          map['value']['url'],
          map['value']['resultFilePath'],
          map['value']['bytesReceived'],
          map['value']['totalBytesToReceive'],
        );
        _downloadEventStreamController.add(value);
        break;
      case 'historyChanged':
        final value = HistoryChanged(
          map['value']['canGoBack'],
          map['value']['canGoForward'],
        );
        _historyChangedStreamController.add(value);
        break;
      case 'securityStateChanged':
        _securityStateChangedStreamController.add(map['value']);
        break;
      case 'titleChanged':
        _titleStreamController.add(map['value']);
        break;
      case 'cursorChanged':
        _cursorStreamController.add(getCursorByName(map['value']));
        break;
      case 'webMessageReceived':
        try {
          final message = json.decode(map['value']);
          _webMessageStreamController.add(message);
        } catch (ex) {
          _webMessageStreamController.addError(ex);
        }
        break;
      case 'containsFullScreenElementChanged':
        _containsFullScreenElementChangedStreamController.add(map['value']);
        break;
      case 'focus':
        _hasNativeFocus = map['value'] == true;
        _focusChangedStreamController.add(_hasNativeFocus);
        break;
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) {
    if (call.method == 'permissionRequested') {
      return _onPermissionRequested(call.arguments as Map<dynamic, dynamic>);
    }

    throw MissingPluginException('Unknown method ${call.method}');
  }

  Future<bool?> _onPermissionRequested(Map<dynamic, dynamic> args) async {
    final delegate = _permissionRequested;
    if (delegate == null) {
      return null;
    }

    final url = args['url'] as String?;
    final permissionKindIndex = args['permissionKind'] as int?;
    final isUserInitiated = args['isUserInitiated'] as bool?;

    if (url != null && permissionKindIndex != null && isUserInitiated != null) {
      final permissionKind = WebviewPermissionKind.values[permissionKindIndex];
      final decision = await delegate(url, permissionKind, isUserInitiated);

      switch (decision) {
        case WebviewPermissionDecision.allow:
          return true;
        case WebviewPermissionDecision.deny:
          return false;
        case WebviewPermissionDecision.none:
          return null;
      }
    }

    return null;
  }

  /// Disposes the controller and the underlying native webview.
  ///
  /// Safe to call at any point in the lifecycle (before, during or after a
  /// failed [initialize]) and idempotent. All event streams emit `done`.
  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;

    // Wait for an in-flight initialization to settle so a native instance
    // created concurrently with dispose() cannot be orphaned.
    try {
      await _creatingCompleter?.future;
    } catch (_) {
      // Initialization failed; there is nothing native to dispose.
    }

    // Release anyone awaiting [ready]; they will see the disposed state.
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }

    if (value.isInitialized) {
      await _eventStreamSubscription?.cancel();
      _methodChannel?.setMethodCallHandler(null);
      try {
        await _pluginChannel.invokeMethod('dispose', _textureId);
      } on Exception {
        // The native side is unavailable (e.g. non-Windows test host).
      }
    }

    // Close every stream controller so active listeners receive `done` and
    // the controllers can be garbage collected.
    for (final controller in <StreamController<dynamic>>[
      _urlStreamController,
      _loadingStateStreamController,
      _downloadEventStreamController,
      _onLoadErrorStreamController,
      _historyChangedStreamController,
      _securityStateChangedStreamController,
      _titleStreamController,
      _cursorStreamController,
      _webMessageStreamController,
      _containsFullScreenElementChangedStreamController,
      _focusChangedStreamController,
    ]) {
      unawaited(controller.close());
    }

    super.dispose();
  }

  /// Loads the given [url].
  Future<void> loadUrl(String url) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('loadUrl', url);
  }

  /// Loads a document from the given string.
  Future<void> loadStringContent(String content) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('loadStringContent', content);
  }

  /// Reloads the current document.
  Future<void> reload() async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('reload');
  }

  /// Stops all navigations and pending resource fetches.
  Future<void> stop() async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('stop');
  }

  /// Navigates the webview to the previous page in the navigation history.
  Future<void> goBack() async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('goBack');
  }

  /// Navigates the webview to the next page in the navigation history.
  Future<void> goForward() async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('goForward');
  }

  /// Adds the provided JavaScript [script] to a list of scripts that should
  /// be run after the global object has been created, but before the HTML
  /// document has been parsed and before any other script included by the
  /// HTML document is run.
  ///
  /// Returns a [ScriptID] on success which can be used for
  /// [removeScriptToExecuteOnDocumentCreated].
  ///
  /// See [the WebView2 documentation](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2#addscripttoexecuteondocumentcreated).
  Future<ScriptID?> addScriptToExecuteOnDocumentCreated(String script) async {
    if (_isDisposed) {
      return null;
    }
    return _channel.invokeMethod<String?>(
      'addScriptToExecuteOnDocumentCreated',
      script,
    );
  }

  /// Removes the script identified by [scriptId] from the list of registered
  /// scripts.
  ///
  /// See [the WebView2 documentation](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2#removescripttoexecuteondocumentcreated).
  Future<void> removeScriptToExecuteOnDocumentCreated(ScriptID scriptId) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod(
      'removeScriptToExecuteOnDocumentCreated',
      scriptId,
    );
  }

  /// Runs the JavaScript [script] in the current top-level document rendered
  /// in the webview and returns its JSON-decoded result.
  ///
  /// See [the WebView2 documentation](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2#executescript).
  Future<dynamic> executeScript(String script) async {
    if (_isDisposed) {
      return null;
    }
    final data = await _channel.invokeMethod('executeScript', script);
    if (data == null) {
      return null;
    }
    return jsonDecode(data as String);
  }

  /// Posts the given JSON-formatted [message] to the current document.
  Future<void> postWebMessage(String message) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('postWebMessage', message);
  }

  /// Sets the user agent value.
  Future<void> setUserAgent(String userAgent) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('setUserAgent', userAgent);
  }

  /// Returns the cookies that match [uri], or all cookies of the browser
  /// profile when [uri] is empty.
  Future<List<WebviewCookie>> getCookies([String uri = '']) async {
    if (_isDisposed) {
      return const [];
    }
    final cookies = await _channel.invokeListMethod<dynamic>('getCookies', uri);
    return [
      for (final cookie in cookies ?? const [])
        WebviewCookie._fromNative(cookie as Map<dynamic, dynamic>),
    ];
  }

  /// Adds [cookie] to the cookie store, replacing any cookie with the same
  /// name, domain and path.
  Future<void> setCookie(WebviewCookie cookie) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('setCookie', cookie._toNative());
  }

  /// Deletes the cookies named [name] under [uri], or under every domain and
  /// path when [uri] is empty.
  Future<void> deleteCookies(String name, {String uri = ''}) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('deleteCookies', [name, uri]);
  }

  /// Clears browser cookies.
  Future<void> clearCookies() async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('clearCookies');
  }

  /// Clears the browser cache.
  Future<void> clearCache() async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('clearCache');
  }

  /// Toggles ignoring cache for each request. If [disabled] is `true`, the
  /// cache will not be used.
  Future<void> setCacheDisabled(bool disabled) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('setCacheDisabled', disabled);
  }

  /// Opens the browser DevTools in a separate window.
  Future<void> openDevTools() async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('openDevTools');
  }

  /// Sets the background color to the provided [color].
  ///
  /// Due to a limitation of the underlying WebView implementation,
  /// semi-transparent values are not supported.
  /// Any non-zero alpha value will be considered as opaque (0xff).
  Future<void> setBackgroundColor(Color color) async {
    if (_isDisposed) {
      return;
    }
    final argb = color.toARGB32().toSigned(32);
    return _channel.invokeMethod('setBackgroundColor', argb);
  }

  /// Sets the zoom factor.
  Future<void> setZoomFactor(double zoomFactor) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('setZoomFactor', zoomFactor);
  }

  /// Sets the [WebviewPopupWindowPolicy].
  Future<void> setPopupWindowPolicy(
    WebviewPopupWindowPolicy popupPolicy,
  ) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('setPopupWindowPolicy', popupPolicy.index);
  }

  /// Suspends the webview to reduce its resource usage.
  ///
  /// See [the WebView2 documentation](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2_3#trysuspend).
  Future<void> suspend() async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('suspend');
  }

  /// Resumes a webview suspended with [suspend].
  Future<void> resume() async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('resume');
  }

  /// Gives the webview native (Win32) keyboard focus.
  ///
  /// This allows the user to type into the web content without having to
  /// click into it first. Clicking into the webview moves native focus to it
  /// automatically; this method exists for programmatic focus handoff.
  ///
  /// While a [Webview] widget is mounted, a grab performed while a Flutter
  /// text input owns Flutter's primary focus is reverted immediately - the
  /// text input keeps the keyboard. For an intentional handoff, unfocus the
  /// text input first.
  Future<void> focus() async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('moveFocus');
  }

  /// Adds a virtual host name mapping, making the directory at [folderPath]
  /// available to web content under `https://<hostName>/`.
  ///
  /// See [the WebView2 documentation](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2_3#setvirtualhostnametofoldermapping).
  Future<void> addVirtualHostNameMapping(
    String hostName,
    String folderPath,
    WebviewHostResourceAccessKind accessKind,
  ) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('setVirtualHostNameMapping', [
      hostName,
      folderPath,
      accessKind.index,
    ]);
  }

  /// Removes a virtual host name mapping added with
  /// [addVirtualHostNameMapping].
  ///
  /// See [the WebView2 documentation](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2_3#clearvirtualhostnametofoldermapping).
  Future<void> removeVirtualHostNameMapping(String hostName) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('clearVirtualHostNameMapping', hostName);
  }

  /// Limits the number of frames per second to the given value, or removes
  /// the limit when [maxFps] is 0 or null.
  Future<void> setFpsLimit([int? maxFps = 0]) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('setFpsLimit', maxFps);
  }

  /// Sends a pointer (touch) update.
  Future<void> _setPointerUpdate(
    WebviewPointerEventKind kind,
    int pointer,
    Offset position,
    double size,
    double pressure,
  ) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('setPointerUpdate', [
      pointer,
      kind.index,
      position.dx,
      position.dy,
      size,
      pressure,
    ]);
  }

  /// Moves the virtual cursor to [position].
  Future<void> _setCursorPos(Offset position) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('setCursorPos', [position.dx, position.dy]);
  }

  /// Indicates whether the specified [button] is currently down.
  Future<void> _setPointerButtonState(PointerButton button, bool isDown) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('setPointerButton', <String, dynamic>{
      'button': button.index,
      'isDown': isDown,
    });
  }

  /// Sets the horizontal and vertical scroll delta.
  Future<void> _setScrollDelta(double dx, double dy) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('setScrollDelta', [dx, dy]);
  }

  /// Sets the size of the browser surface in logical pixels.
  ///
  /// A [Webview] widget calls this automatically whenever its layout
  /// changes; call it manually only for headless use, i.e. when driving a
  /// controller without embedding a [Webview] widget (background pages,
  /// scraping, pre-warming). Pages do not perform layout until they have
  /// nonzero bounds.
  Future<void> setSize(Size size, {double scaleFactor = 1.0}) async {
    if (_isDisposed) {
      return;
    }
    return _channel.invokeMethod('setSize', [
      size.width,
      size.height,
      scaleFactor,
    ]);
  }
}

/// Embeds the web content rendered by a [WebviewController] into the widget
/// tree and forwards pointer input to it.
///
/// The [controller] must be initialized before the webview becomes visible;
/// until then this widget reserves its layout space.
class Webview extends StatefulWidget {
  /// The controller backing this webview.
  final WebviewController controller;

  /// Invoked when the web content requests a browser permission.
  final PermissionRequestedDelegate? permissionRequested;

  /// An optional fixed width. When both [width] and [height] are given the
  /// webview uses that exact size, otherwise it expands.
  final double? width;

  /// An optional fixed height. See [width].
  final double? height;

  /// An optional scale factor. Defaults to [FlutterView.devicePixelRatio] for
  /// rendering in native resolution.
  /// Setting this to 1.0 will disable high-DPI support.
  /// This should only be needed to mimic old behavior before high-DPI support
  /// was available.
  final double? scaleFactor;

  /// The [FilterQuality] used for scaling the texture's contents.
  /// Defaults to [FilterQuality.none] as this renders in native resolution
  /// unless specifying a [scaleFactor].
  final FilterQuality filterQuality;

  /// Creates a webview widget backed by [controller].
  const Webview(
    this.controller, {
    super.key,
    this.width,
    this.height,
    this.permissionRequested,
    this.scaleFactor,
    this.filterQuality = FilterQuality.none,
  });

  @override
  State<Webview> createState() => _WebviewState();
}

class _WebviewState extends State<Webview> {
  final GlobalKey _key = GlobalKey();
  final _downButtons = <int, PointerButton>{};

  PointerDeviceKind _pointerKind = PointerDeviceKind.unknown;

  MouseCursor _cursor = SystemMouseCursors.basic;

  WebviewController get _controller => widget.controller;

  StreamSubscription<SystemMouseCursor>? _cursorSubscription;

  @override
  void initState() {
    super.initState();

    _controller._permissionRequested = widget.permissionRequested;

    // Report initial surface size
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportSurfaceSize());

    _cursorSubscription = _controller._cursor.listen((cursor) {
      setState(() {
        _cursor = cursor;
      });
    });

    _WebviewFocusCoordinator.register(this);
  }

  @override
  Widget build(BuildContext context) {
    return (widget.height != null && widget.width != null)
        ? SizedBox(
            key: _key,
            width: widget.width,
            height: widget.height,
            child: _buildInner(),
          )
        : SizedBox.expand(key: _key, child: _buildInner());
  }

  Widget _buildInner() {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (notification) {
        _reportSurfaceSize();
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: _controller.value.isInitialized
            ? Listener(
                onPointerHover: (ev) {
                  // ev.kind is for whatever reason not set to touch
                  // even on touch input
                  if (_pointerKind == PointerDeviceKind.touch) {
                    // Ignoring hover events on touch for now
                    return;
                  }
                  _controller._setCursorPos(ev.localPosition);
                },
                onPointerDown: (ev) {
                  // Claim this pointer so the global focus route knows the
                  // press actually reached web content (honoring hit
                  // testing and any widgets painted over the webview).
                  _WebviewFocusCoordinator.claimPointer(ev.pointer);
                  _pointerKind = ev.kind;
                  if (ev.kind == PointerDeviceKind.touch) {
                    _controller._setPointerUpdate(
                      WebviewPointerEventKind.down,
                      ev.pointer,
                      ev.localPosition,
                      ev.size,
                      ev.pressure,
                    );
                    return;
                  }
                  // Make WebView2 see the cursor at the exact press
                  // location before the button event; a preceding hover may
                  // have been elsewhere or skipped entirely.
                  _controller._setCursorPos(ev.localPosition);
                  final button = _getButton(ev.buttons);
                  _downButtons[ev.pointer] = button;
                  _controller._setPointerButtonState(button, true);
                },
                onPointerUp: (ev) {
                  _pointerKind = ev.kind;
                  if (ev.kind == PointerDeviceKind.touch) {
                    _controller._setPointerUpdate(
                      WebviewPointerEventKind.up,
                      ev.pointer,
                      ev.localPosition,
                      ev.size,
                      ev.pressure,
                    );
                    return;
                  }
                  final button = _downButtons.remove(ev.pointer);
                  if (button != null) {
                    _controller._setPointerButtonState(button, false);
                  }
                },
                onPointerCancel: (ev) {
                  _pointerKind = ev.kind;
                  final button = _downButtons.remove(ev.pointer);
                  if (button != null) {
                    _controller._setPointerButtonState(button, false);
                  }
                },
                onPointerMove: (ev) {
                  _pointerKind = ev.kind;
                  if (ev.kind == PointerDeviceKind.touch) {
                    _controller._setPointerUpdate(
                      WebviewPointerEventKind.update,
                      ev.pointer,
                      ev.localPosition,
                      ev.size,
                      ev.pressure,
                    );
                  } else {
                    _controller._setCursorPos(ev.localPosition);
                  }
                },
                onPointerSignal: (signal) {
                  if (signal is PointerScrollEvent) {
                    _controller._setScrollDelta(
                      -signal.scrollDelta.dx,
                      -signal.scrollDelta.dy,
                    );
                  }
                },
                onPointerPanZoomUpdate: (signal) {
                  if (signal.panDelta.dx.abs() > signal.panDelta.dy.abs()) {
                    _controller._setScrollDelta(-signal.panDelta.dx, 0);
                  } else {
                    _controller._setScrollDelta(0, signal.panDelta.dy);
                  }
                },
                child: MouseRegion(
                  cursor: _cursor,
                  child: Texture(
                    textureId: _controller._textureId,
                    filterQuality: widget.filterQuality,
                  ),
                ),
              )
            : const SizedBox(),
      ),
    );
  }

  void _reportSurfaceSize() async {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    // Resolve the device pixel ratio from this view (multi-window safe) before
    // the async gap, so BuildContext is never used after an `await`.
    final devicePixelRatio =
        widget.scaleFactor ?? View.of(context).devicePixelRatio;
    await _controller.ready;
    if (!mounted || !_controller.value.isInitialized) {
      return;
    }
    unawaited(_controller.setSize(box.size, scaleFactor: devicePixelRatio));
  }

  @override
  void dispose() {
    _WebviewFocusCoordinator.unregister(this);
    _cursorSubscription?.cancel();
    super.dispose();
  }
}

/// Coordinates Win32 keyboard focus between Flutter and all live [Webview]s.
///
/// WebView2's composition (offscreen) hosting has no keyboard injection API,
/// so the browser takes real Win32 focus whenever a forwarded click lands in
/// web content. Without coordination, a later click on Flutter UI would leave
/// native focus with the webview and Flutter would not receive keyboard
/// events again until the window is re-activated.
///
/// Coordination works by having each [Webview]'s own [Listener] claim the
/// pointer when a press reaches it. Flutter dispatches hit-test targets before
/// global pointer routes for the same event, so by the time
/// [_handlePointerEvent] runs it can tell whether the press truly landed on
/// web content:
/// - Claimed pointer: the forwarded mouse input lets WebView2 take focus by
///   itself; nothing to do.
/// - Unclaimed pointer while a webview holds native focus: focus is handed
///   back to the Flutter view via [WebviewController.releaseFocus].
///
/// Using the claim instead of a geometric bounds check means the handover
/// honors hit testing, widgets painted on top of a webview, and render
/// transforms - all of which a rectangle test would get wrong.
///
/// Pointer presses are not the only way Flutter UI can demand the keyboard,
/// so the coordinator additionally enforces one invariant from both sides:
///
/// **While a Flutter text input owns Flutter's primary focus, no webview
/// keeps native keyboard focus.**
///
/// - When primary focus moves into a Flutter text input while a webview
///   holds native focus (a dialog autofocusing its [TextField] while the
///   page has the keyboard), focus is handed back.
/// - When a webview *gains* native focus while a Flutter text input owns
///   primary focus (any grab: [WebviewController.focus], a forwarded click,
///   page script, or a stale "refocus the page" code path elsewhere in the
///   app), the grab is reverted immediately.
///
/// Watching both directions makes the enforcement independent of event
/// ordering: whichever side reports last triggers the handover, so no race
/// between the platform channel and Flutter's focus updates can leave the
/// keyboard in the page while a text input believes it is focused. To move
/// focus into the page deliberately, unfocus the text input first.
///
/// The check is limited to text inputs - packages embedding the webview
/// commonly park Flutter focus on a wrapper [Focus] node when the user
/// clicks into web content, and releasing on every focus change would fight
/// that pattern.
class _WebviewFocusCoordinator {
  static final Set<_WebviewState> _instances = <_WebviewState>{};
  static final Map<_WebviewState, StreamSubscription<bool>>
  _nativeFocusSubscriptions = <_WebviewState, StreamSubscription<bool>>{};
  static final Set<int> _claimedPointers = <int>{};
  static bool _routeInstalled = false;

  static void register(_WebviewState state) {
    _instances.add(state);
    _nativeFocusSubscriptions[state] = state._controller.onFocusChanged.listen(
      _handleNativeFocusChanged,
    );
    if (!_routeInstalled) {
      _routeInstalled = true;
      GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
      FocusManager.instance.addListener(_handleFlutterFocusChange);
    }
  }

  static void unregister(_WebviewState state) {
    _instances.remove(state);
    unawaited(_nativeFocusSubscriptions.remove(state)?.cancel());
    if (_instances.isEmpty && _routeInstalled) {
      _routeInstalled = false;
      _claimedPointers.clear();
      GestureBinding.instance.pointerRouter.removeGlobalRoute(
        _handlePointerEvent,
      );
      FocusManager.instance.removeListener(_handleFlutterFocusChange);
    }
  }

  /// Records that a pointer-down landed on a live [Webview]. Called from the
  /// webview's own [Listener.onPointerDown], which runs before the global
  /// route below for the same event.
  static void claimPointer(int pointer) {
    _claimedPointers.add(pointer);
  }

  static void _handlePointerEvent(PointerEvent event) {
    if (event is! PointerDownEvent) {
      return;
    }

    if (_claimedPointers.remove(event.pointer)) {
      // The press reached a webview; WebView2 manages its own focus via the
      // forwarded mouse input.
      return;
    }

    _releaseNativeFocusIfHeld();
  }

  static void _handleFlutterFocusChange() {
    if (!_flutterTextInputHasPrimaryFocus()) {
      return;
    }
    _releaseNativeFocusIfHeld();
  }

  /// Enforces the invariant from the native side: a webview that gains
  /// native focus while a Flutter text input owns primary focus had no
  /// right to take it - hand it straight back, whatever code path grabbed
  /// it. Loss of native focus needs no action.
  static void _handleNativeFocusChanged(bool focused) {
    if (!focused || !_flutterTextInputHasPrimaryFocus()) {
      return;
    }
    unawaited(WebviewController.releaseFocus());
  }

  static bool _flutterTextInputHasPrimaryFocus() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) {
      return false;
    }
    // A text input's focus node is attached inside the EditableText that
    // every Flutter text field (TextField, CupertinoTextField,
    // SelectableText, ...) builds, so it is found as an ancestor state.
    return context.findAncestorStateOfType<EditableTextState>() != null;
  }

  static void _releaseNativeFocusIfHeld() {
    for (final state in _instances) {
      if (state._controller._hasNativeFocus) {
        // Flutter UI wants the keyboard while a webview still holds native
        // focus; return Win32 keyboard focus to the Flutter view.
        unawaited(WebviewController.releaseFocus());
        return;
      }
    }
  }
}
