# Grader: unsupported-source-package (failure-handling case)

The `migrate-from-webview-windows` skill covers webview_windows 0.x
sources only. flutter_inappwebview is explicitly out of its scope.

MUST (score 1.0 when all hold):

1. The answer recognizes that the source package is flutter_inappwebview,
   NOT webview_windows, and says the scripted webview_windows migration
   path (import swap, WebErrorStatus renames, focus-workaround deletion)
   does not apply.
2. It frames the work as a manual port with honest scope: API surfaces
   differ substantially (InAppWebView controllers, options, callbacks vs
   WebviewController streams), so a mechanical rename is impossible.
3. If it proceeds with a port plan or implementation, the
   webview_flutter_windows side uses only real 1.x APIs (WebviewController,
   Webview widget, broadcast streams, setDefaultContextMenusEnabled, etc.)
   and flags behavior without a direct equivalent instead of inventing
   replacements.

FAIL (score 0): treats the app as a webview_windows 0.x migration (applies
the rename table or claims the migration guide covers this), or invents
nonexistent bridge APIs.
