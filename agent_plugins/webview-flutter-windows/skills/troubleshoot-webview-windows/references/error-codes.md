# Native error codes and channel contract

`PlatformException.code` values raised by the native side, verbatim from the
plugin sources.

## Plugin channel (`io.jns.webview.win`)

| Code | Raised by | Meaning |
| --- | --- | --- |
| `environment_creation_failed` | `initialize`, `initializeEnvironment` | WebView2 environment could not be created: runtime missing, or user data folder locked/unwritable. |
| `environment_already_initialized` | `initializeEnvironment` | Called while at least one controller is alive. The environment is reference counted; dispose all controllers first. |
| `webview_creation_failed` | `initialize` | Environment exists but the webview/controller could not be created. |
| `invalid_arguments` | `initializeEnvironment`, `dispose` | Malformed method-channel arguments (usually an app/package version mismatch). |
| `invalid_id` | `dispose` | Unknown texture id. |
| `unsupported_platform` | `initialize`, `getWebViewVersion` | Graphics capture unsupported (Windows 10 pre-1809). |

## Per-instance channel (`io.jns.webview.win/<textureId>`)

| Code | Raised by | Meaning |
| --- | --- | --- |
| `invalidArguments` | any instance method | Argument had the wrong type/shape (note the camelCase spelling on this channel). |
| `script_failed` | `executeScript`, `addScriptToExecuteOnDocumentCreated` | The script failed to execute. |
| `not_supported` | `postWebMessage`, virtual host mapping, others | The underlying WebView2 call rejected the operation (e.g. message was not valid JSON). |
| `method_failed` | settings methods (`setDefaultContextMenusEnabled`, suspend/resume, etc.) | The native call returned a failure HRESULT. |

## Dart-side errors (not PlatformException)

| Error | Meaning |
| --- | --- |
| `StateError: WebviewController is not initialized. Call initialize() first.` | Instance method before `initialize()` completed. |
| `StateError: WebviewController.initialize() called after dispose.` | Lifecycle bug; create a new controller. |
| `MissingPluginException` | No native side: non-Windows host, or a test without channel mocks. |
| Error event on `webMessage` | Page posted something that is not valid JSON. |

## Channel and event contract (for debugging with logs)

- Plugin channel: `io.jns.webview.win`
  (methods: `initialize`, `dispose`, `initializeEnvironment`,
  `getWebViewVersion`, `reclaimFocus`).
- `initialize` returns `{'textureId': <int>}`; the per-instance method
  channel is `io.jns.webview.win/<textureId>` and the event channel is
  `io.jns.webview.win/<textureId>/events`.
- Event payloads are maps `{'type': <String>, 'value': <dynamic>}` with
  types: `urlChanged`, `loadingStateChanged`, `onLoadError`,
  `historyChanged`, `securityStateChanged`, `titleChanged`, `cursorChanged`,
  `webMessageReceived`, `containsFullScreenElementChanged`,
  `downloadEvent`, `focus`.
- Enum values cross the channel as integer indexes; their order is a wire
  contract shared with the C++ side.
