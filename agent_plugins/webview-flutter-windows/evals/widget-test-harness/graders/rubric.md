# Grader: widget-test-harness

Score 1.0 only if ALL MUST items hold.
This case exercises the `test-webview-windows` skill.

MUST:

1. The mock for the plugin channel `io.jns.webview.win` answers
   `initialize` with a MAP shaped `{'textureId': <int>}`. A bare int,
   string, or generic "success for everything" reply fails this item (the
   real controller reads `reply['textureId']` and would crash).
2. Mocks (or routes) the per-instance method channel
   `io.jns.webview.win/<textureId>` so controller methods and the widget's
   automatic `setSize` do not error.
3. Provides a mock stream handler (or equivalent) for the event channel
   `io.jns.webview.win/<textureId>/events` so the controller's event
   subscription does not fail.
4. Uses `tester.runAsync(...)` around work that awaits the controller's
   platform futures (initialize/dispose or an equivalent settling call),
   consistent with the fake-async zone limitation, OR structures the test
   so those futures demonstrably complete (e.g. settling via
   `tester.runAsync(() => Future.delayed(Duration.zero))` before pumping).
5. Test 1 asserts `CircularProgressIndicator` before init completes; test 2
   asserts the `Key('url-field')` widget after init completes; assertions
   are pump-driven, not arbitrary sleeps.

SHOULD:

6. Handlers are removed in tearDown (test isolation).
7. Uses `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger`
   `setMockMethodCallHandler` / `setMockStreamHandler` (the supported
   flutter_test surface) rather than deprecated APIs.

FAIL (score 0): item 1 wrong (the tests would crash or hang against the
real package), or the answer skips mocking and requires Windows.

Executable check (strongest form, use when running the eval manually): put
the produced files in a scratch Flutter project depending on
webview_flutter_windows and run `flutter test`; both tests must pass. Known
failure signatures: `Invalid argument: Instance of
'MockStreamHandlerEventSink'` (arrow-bodied stream-handler callbacks) and
"No Material widget found" (missing MaterialApp/Scaffold wrapper).
