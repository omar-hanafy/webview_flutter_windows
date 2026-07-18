# Grader: migrate-legacy-app

Score 1.0 only if ALL MUST items hold; each miss caps the score lower.
This case exercises the `migrate-from-webview-windows` skill.

MUST (correct migration):

1. Performs the migration (does not refuse or claim the package might not
   exist) and does NOT invent APIs absent from webview_flutter_windows 1.x.
2. `pubspec.yaml`: `webview_windows` removed entirely and
   `webview_flutter_windows` (any ^1.x constraint) added; the two never
   coexist. SDK floor raised to `^3.12.0` (or an equivalent >=3.12 floor).
3. Import changed to `package:webview_flutter_windows/webview_flutter_windows.dart`.
4. `WebErrorStatus.WebErrorStatusTimeout` becomes `WebErrorStatus.timeout`
   and `WebErrorStatusDisconnected` becomes `WebErrorStatus.disconnected`.
5. The `url.listen` (and error listen) calls are moved BEFORE `loadUrl`,
   with the buffered-stream comment corrected or removed (1.x broadcast
   streams drop unheard events).
6. The `window_manager` focus workaround (Listener + windowManager.focus +
   `_refocusTimer`) is deleted, not ported; `window_manager` may be removed
   from pubspec since nothing else uses it.

SHOULD (quality signals, small deductions if missing):

7. Wraps or otherwise handles `initialize()` failure (failures now complete
   the future) or mentions the StateError lifecycle hardening.
8. The behavioral-differences list mentions broadcast streams, the focus
   fix (upstream issue 230), and the WebErrorStatus renames.
9. Mentions that WebView2 default context menus are disabled by default in
   the fork (upstream showed them), with `setDefaultContextMenusEnabled(true)`
   as the opt-in.

FAIL (score 0): refuses the migration, keeps both packages, invents methods
that do not exist in the 1.x API, or leaves prefixed WebErrorStatus names.
