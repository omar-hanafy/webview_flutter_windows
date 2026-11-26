/// @docImport 'package:webview_flutter_windows/src/webview.dart';
library;

/// The document loading state.
// Order must match WebviewLoadingState (see webview.h)
enum LoadingState {
  /// No document is loaded.
  none,

  /// A document is loading.
  loading,

  /// Navigation has completed.
  navigationCompleted,
}

/// A pointer button.
// Order must match WebviewPointerButton (see webview.h)
enum PointerButton {
  /// No button.
  none,

  /// The primary (usually left) mouse button.
  primary,

  /// The secondary (usually right) mouse button.
  secondary,

  /// The tertiary (middle) mouse button.
  tertiary,
}

/// The kind of a [WebviewDownloadEvent].
enum WebviewDownloadEventKind {
  /// A download has started.
  downloadStarted,

  /// A download has completed.
  downloadCompleted,

  /// A download made progress.
  downloadProgress,
}

/// The kind of a forwarded pointer event.
// Order must match WebviewPointerEventKind (see webview.h)
enum WebviewPointerEventKind {
  /// The pointer activated the window.
  activate,

  /// The pointer made contact.
  down,

  /// The pointer entered the surface.
  enter,

  /// The pointer left the surface.
  leave,

  /// The pointer contact lifted.
  up,

  /// The pointer moved or its properties changed.
  update,
}

/// The kind of a browser permission request.
// Order must match WebviewPermissionKind (see webview.h)
enum WebviewPermissionKind {
  /// An unknown permission.
  unknown,

  /// Microphone access.
  microphone,

  /// Camera access.
  camera,

  /// Geolocation access.
  geoLocation,

  /// Web notifications.
  notifications,

  /// Generic sensor access.
  otherSensors,

  /// Clipboard read access.
  clipboardRead,
}

/// The reply to a browser permission request.
enum WebviewPermissionDecision {
  /// Defer to the WebView2 default behavior.
  none,

  /// Grant the permission.
  allow,

  /// Deny the permission.
  deny,
}

/// The policy for popup requests.
///
/// [allow] allows popups and will create new windows.
/// [deny] suppresses popups.
/// [sameWindow] displays popup contents in the current WebView.
enum WebviewPopupWindowPolicy {
  /// Allow popups in new windows.
  allow,

  /// Suppress popups.
  deny,

  /// Display popup contents in the current webview.
  sameWindow,
}

/// The kind of cross origin resource access allowed for host resources of a
/// virtual host mapping.
///
/// [deny] all cross origin requests are denied.
/// [allow] all cross origin requests are allowed.
/// [denyCors] sub resource cross origin requests are allowed, otherwise
/// denied.
///
/// For more detailed information, please refer to
/// [Microsoft's documentation](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2#corewebview2_host_resource_access_kind).
// Order must match WebviewHostResourceAccessKind (see webview.h)
enum WebviewHostResourceAccessKind {
  /// All cross origin resource access is denied.
  deny,

  /// All cross origin resource access is allowed.
  allow,

  /// Cross origin resource access is allowed for sub resources, denied
  /// otherwise.
  denyCors,
}

/// The SameSite policy of a cookie.
// Order must match COREWEBVIEW2_COOKIE_SAME_SITE_KIND (the native value is
// used as an index into this enum).
enum WebviewCookieSameSite {
  /// No SameSite restriction; the cookie is sent with all requests.
  none,

  /// The cookie is withheld on cross-site sub-requests but sent on top-level
  /// navigations.
  lax,

  /// The cookie is only sent for same-site requests.
  strict,
}

/// The error status of a failed navigation, reported on
/// [WebviewController.onLoadError].
///
/// Mirrors `COREWEBVIEW2_WEB_ERROR_STATUS`; see
/// [Microsoft's documentation](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2#corewebview2_web_error_status).
// Order must match COREWEBVIEW2_WEB_ERROR_STATUS (the native value is used as
// an index into this enum).
enum WebErrorStatus {
  /// An unknown error occurred.
  unknown,

  /// The SSL certificate common name does not match the web address.
  certificateCommonNameIsIncorrect,

  /// The SSL certificate has expired.
  certificateExpired,

  /// The SSL client certificate contains errors.
  clientCertificateContainsErrors,

  /// The SSL certificate has been revoked.
  certificateRevoked,

  /// The SSL certificate is invalid.
  certificateIsInvalid,

  /// The host is unreachable.
  serverUnreachable,

  /// The connection has timed out.
  timeout,

  /// The server returned an invalid or unrecognized response.
  errorHttpInvalidServerResponse,

  /// The connection was aborted.
  connectionAborted,

  /// The connection was reset.
  connectionReset,

  /// The internet connection has been lost.
  disconnected,

  /// A connection to the destination was not established.
  cannotConnect,

  /// The provided host name was not able to be resolved.
  hostNameNotResolved,

  /// The operation was canceled.
  operationCanceled,

  /// The request redirect failed.
  redirectFailed,

  /// An unexpected error occurred.
  unexpectedError,

  /// The request requires authentication credentials.
  validAuthenticationCredentialsRequired,

  /// The request requires proxy authentication.
  validProxyAuthenticationRequired,
}
