#include "webview_bridge.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_result_functions.h>

#include <format>

#include "texture_bridge_gpu.h"
#include "util/cursor_util.h"

namespace {

// ---------------------------------------------------------------------------
// Wire-format contract with the Dart side.
//
// Enum values cross the method/event channels as plain integers and the Dart
// side (lib/src/enums.dart) decodes them as indexes into the corresponding
// Dart enums. The integer values pinned below ARE the protocol: if any of
// these asserts fires, the matching Dart enum (and its contract test in
// test/webview_flutter_windows_test.dart) must be updated in the same change.
// ---------------------------------------------------------------------------

static_assert(static_cast<int>(WebviewLoadingState::None) == 0);
static_assert(static_cast<int>(WebviewLoadingState::Loading) == 1);
static_assert(static_cast<int>(WebviewLoadingState::NavigationCompleted) == 2);

static_assert(static_cast<int>(WebviewPointerButton::None) == 0);
static_assert(static_cast<int>(WebviewPointerButton::Primary) == 1);
static_assert(static_cast<int>(WebviewPointerButton::Secondary) == 2);
static_assert(static_cast<int>(WebviewPointerButton::Tertiary) == 3);

static_assert(static_cast<int>(WebviewPointerEventKind::Activate) == 0);
static_assert(static_cast<int>(WebviewPointerEventKind::Down) == 1);
static_assert(static_cast<int>(WebviewPointerEventKind::Enter) == 2);
static_assert(static_cast<int>(WebviewPointerEventKind::Leave) == 3);
static_assert(static_cast<int>(WebviewPointerEventKind::Up) == 4);
static_assert(static_cast<int>(WebviewPointerEventKind::Update) == 5);

static_assert(static_cast<int>(WebviewDownloadEventKind::DownloadStarted) ==
              0);
static_assert(static_cast<int>(WebviewDownloadEventKind::DownloadCompleted) ==
              1);
static_assert(static_cast<int>(WebviewDownloadEventKind::DownloadProgress) ==
              2);

static_assert(static_cast<int>(WebviewPermissionKind::Unknown) == 0);
static_assert(static_cast<int>(WebviewPermissionKind::Microphone) == 1);
static_assert(static_cast<int>(WebviewPermissionKind::Camera) == 2);
static_assert(static_cast<int>(WebviewPermissionKind::GeoLocation) == 3);
static_assert(static_cast<int>(WebviewPermissionKind::Notifications) == 4);
static_assert(static_cast<int>(WebviewPermissionKind::OtherSensors) == 5);
static_assert(static_cast<int>(WebviewPermissionKind::ClipboardRead) == 6);

static_assert(static_cast<int>(WebviewHostResourceAccessKind::Deny) == 0);
static_assert(static_cast<int>(WebviewHostResourceAccessKind::Allow) == 1);
static_assert(static_cast<int>(WebviewHostResourceAccessKind::DenyCors) == 2);

// Cookie SameSite values cross the channel verbatim; the Dart
// WebviewCookieSameSite enum decodes them as indexes.
static_assert(COREWEBVIEW2_COOKIE_SAME_SITE_KIND_NONE == 0);
static_assert(COREWEBVIEW2_COOKIE_SAME_SITE_KIND_LAX == 1);
static_assert(COREWEBVIEW2_COOKIE_SAME_SITE_KIND_STRICT == 2);

// onLoadError forwards COREWEBVIEW2_WEB_ERROR_STATUS verbatim; the Dart
// WebErrorStatus enum mirrors the first 19 values and maps anything newer to
// WebErrorStatus.unknown. Pin the SDK values this plugin was built against so
// an SDK that breaks the established numbering cannot slip through.
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN == 0);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_COMMON_NAME_IS_INCORRECT ==
              1);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_EXPIRED == 2);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_CLIENT_CERTIFICATE_CONTAINS_ERRORS ==
              3);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_REVOKED == 4);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_IS_INVALID == 5);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_SERVER_UNREACHABLE == 6);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_TIMEOUT == 7);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_ERROR_HTTP_INVALID_SERVER_RESPONSE ==
              8);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_ABORTED == 9);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_RESET == 10);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_DISCONNECTED == 11);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_CANNOT_CONNECT == 12);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_HOST_NAME_NOT_RESOLVED == 13);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED == 14);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_REDIRECT_FAILED == 15);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_UNEXPECTED_ERROR == 16);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_VALID_AUTHENTICATION_CREDENTIALS_REQUIRED ==
              17);
static_assert(COREWEBVIEW2_WEB_ERROR_STATUS_VALID_PROXY_AUTHENTICATION_REQUIRED ==
              18);

constexpr auto kErrorInvalidArgs = "invalidArguments";

constexpr auto kMethodLoadUrl = "loadUrl";
constexpr auto kMethodLoadStringContent = "loadStringContent";
constexpr auto kMethodReload = "reload";
constexpr auto kMethodStop = "stop";
constexpr auto kMethodGoBack = "goBack";
constexpr auto kMethodGoForward = "goForward";
constexpr auto kMethodAddScriptToExecuteOnDocumentCreated =
    "addScriptToExecuteOnDocumentCreated";
constexpr auto kMethodRemoveScriptToExecuteOnDocumentCreated =
    "removeScriptToExecuteOnDocumentCreated";
constexpr auto kMethodExecuteScript = "executeScript";
constexpr auto kMethodPostWebMessage = "postWebMessage";
constexpr auto kMethodSetSize = "setSize";
constexpr auto kMethodSetCursorPos = "setCursorPos";
constexpr auto kMethodSetPointerUpdate = "setPointerUpdate";
constexpr auto kMethodSetPointerButton = "setPointerButton";
constexpr auto kMethodSetScrollDelta = "setScrollDelta";
constexpr auto kMethodSetUserAgent = "setUserAgent";
constexpr auto kMethodSetBackgroundColor = "setBackgroundColor";
constexpr auto kMethodSetZoomFactor = "setZoomFactor";
constexpr auto kMethodOpenDevTools = "openDevTools";
constexpr auto kMethodSuspend = "suspend";
constexpr auto kMethodResume = "resume";
constexpr auto kMethodSetVirtualHostNameMapping = "setVirtualHostNameMapping";
constexpr auto kMethodClearVirtualHostNameMapping =
    "clearVirtualHostNameMapping";
constexpr auto kMethodGetCookies = "getCookies";
constexpr auto kMethodSetCookie = "setCookie";
constexpr auto kMethodDeleteCookies = "deleteCookies";
constexpr auto kMethodClearCookies = "clearCookies";
constexpr auto kMethodClearCache = "clearCache";
constexpr auto kMethodSetCacheDisabled = "setCacheDisabled";
constexpr auto kMethodSetPopupWindowPolicy = "setPopupWindowPolicy";
constexpr auto kMethodSetFpsLimit = "setFpsLimit";
constexpr auto kMethodMoveFocus = "moveFocus";

constexpr auto kEventType = "type";
constexpr auto kEventValue = "value";

constexpr auto kErrorNotSupported = "not_supported";
constexpr auto kScriptFailed = "script_failed";
constexpr auto kMethodFailed = "method_failed";

static const std::optional<std::pair<double, double>> GetPointFromArgs(
    const flutter::EncodableValue* args) {
  const flutter::EncodableList* list =
      std::get_if<flutter::EncodableList>(args);
  if (!list || list->size() != 2) {
    return std::nullopt;
  }
  const auto x = std::get_if<double>(&(*list)[0]);
  const auto y = std::get_if<double>(&(*list)[1]);
  if (!x || !y) {
    return std::nullopt;
  }
  return std::make_pair(*x, *y);
}

static const std::optional<std::tuple<double, double, double>>
GetPointAndScaleFactorFromArgs(const flutter::EncodableValue* args) {
  const flutter::EncodableList* list =
      std::get_if<flutter::EncodableList>(args);
  if (!list || list->size() != 3) {
    return std::nullopt;
  }
  const auto x = std::get_if<double>(&(*list)[0]);
  const auto y = std::get_if<double>(&(*list)[1]);
  const auto z = std::get_if<double>(&(*list)[2]);
  if (!x || !y || !z) {
    return std::nullopt;
  }
  return std::make_tuple(*x, *y, *z);
}

}  // namespace

WebviewBridge::WebviewBridge(flutter::BinaryMessenger* messenger,
                             flutter::TextureRegistrar* texture_registrar,
                             GraphicsContext* graphics_context,
                             std::unique_ptr<Webview> webview)
    : webview_(std::move(webview)), texture_registrar_(texture_registrar) {
  texture_bridge_ =
      std::make_unique<TextureBridgeGpu>(graphics_context, webview_->surface());

  flutter_texture_ =
      std::make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(
          kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
          [bridge = static_cast<TextureBridgeGpu*>(texture_bridge_.get())](
              size_t width,
              size_t height) -> const FlutterDesktopGpuSurfaceDescriptor* {
            return bridge->GetSurfaceDescriptor(width, height);
          }));

  texture_id_ = texture_registrar->RegisterTexture(flutter_texture_.get());
  texture_bridge_->SetOnFrameAvailable(
      [this]() { texture_registrar_->MarkTextureFrameAvailable(texture_id_); });
  // texture_bridge_->SetOnSurfaceSizeChanged([this](Size size) {
  //  webview_->SetSurfaceSize(size.width, size.height);
  //});

  const auto method_channel_name =
      std::format("io.jns.webview.win/{}", texture_id_);
  method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, method_channel_name,
          &flutter::StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });

  const auto event_channel_name =
      std::format("io.jns.webview.win/{}/events", texture_id_);
  event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          messenger, event_channel_name,
          &flutter::StandardMethodCodec::GetInstance());

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue* arguments,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                 events) {
        event_sink_ = std::move(events);
        RegisterEventHandlers();
        return nullptr;
      },
      [this](const flutter::EncodableValue* arguments) {
        event_sink_ = nullptr;
        return nullptr;
      });

  event_channel_->SetStreamHandler(std::move(handler));
}

WebviewBridge::~WebviewBridge() {
  method_channel_->SetMethodCallHandler(nullptr);
  texture_registrar_->UnregisterTexture(texture_id_);
  // Tear down explicitly in a safe order: ~Webview closes the WebView2
  // controller, which can synchronously raise LostFocus and try to emit
  // through the event sink. Relying on member destruction order alone would
  // destroy the sink first, leaving that callback with a dangling reference.
  event_sink_ = nullptr;
  webview_ = nullptr;
}

void WebviewBridge::RegisterEventHandlers() {
  webview_->OnUrlChanged([this](const std::string& url) {
    const auto event = flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue(kEventType),
         flutter::EncodableValue("urlChanged")},
        {flutter::EncodableValue(kEventValue), flutter::EncodableValue(url)},
    });
    EmitEvent(event);
  });

  webview_->OnLoadError([this](COREWEBVIEW2_WEB_ERROR_STATUS web_status) {
    const auto event = flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue(kEventType),
         flutter::EncodableValue("onLoadError")},
        {flutter::EncodableValue(kEventValue),
         flutter::EncodableValue(static_cast<int>(web_status))},
    });
    EmitEvent(event);
  });

  webview_->OnLoadingStateChanged([this](WebviewLoadingState state) {
    const auto event = flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue(kEventType),
         flutter::EncodableValue("loadingStateChanged")},
        {flutter::EncodableValue(kEventValue),
         flutter::EncodableValue(static_cast<int>(state))},
    });
    EmitEvent(event);
  });

  webview_->OnDownloadEvent([this](WebviewDownloadEvent webviewDownloadEvent) {
    const auto event = flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue(kEventType),
         flutter::EncodableValue("downloadEvent")},
        {flutter::EncodableValue(kEventValue),
         flutter::EncodableValue(flutter::EncodableMap{
             {flutter::EncodableValue("kind"),
              flutter::EncodableValue(
                  static_cast<int>(webviewDownloadEvent.kind))},
             {flutter::EncodableValue("url"),
              flutter::EncodableValue(webviewDownloadEvent.url)},
             {flutter::EncodableValue("resultFilePath"),
              flutter::EncodableValue(webviewDownloadEvent.resultFilePath)},
             {flutter::EncodableValue("bytesReceived"),
              flutter::EncodableValue(webviewDownloadEvent.bytesReceived)},
             {flutter::EncodableValue("totalBytesToReceive"),
              flutter::EncodableValue(
                  webviewDownloadEvent.totalBytesToReceive)},
         })}});
    EmitEvent(event);
  });

  webview_->OnHistoryChanged([this](WebviewHistoryChanged historyChanged) {
    const auto event = flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue(kEventType),
         flutter::EncodableValue("historyChanged")},
        {flutter::EncodableValue(kEventValue),
         flutter::EncodableValue(flutter::EncodableMap{
             {flutter::EncodableValue("canGoBack"),
              flutter::EncodableValue(
                  static_cast<bool>(historyChanged.can_go_back))},
             {flutter::EncodableValue("canGoForward"),
              flutter::EncodableValue(
                  static_cast<bool>(historyChanged.can_go_forward))},
         })},
    });
    EmitEvent(event);
  });

  webview_->OnDevtoolsProtocolEvent([this](const std::string& json) {
    const auto event = flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue(kEventType),
         flutter::EncodableValue("securityStateChanged")},
        {flutter::EncodableValue(kEventValue), flutter::EncodableValue(json)}});
    EmitEvent(event);
  });

  webview_->OnDocumentTitleChanged([this](const std::string& title) {
    const auto event = flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue(kEventType),
         flutter::EncodableValue("titleChanged")},
        {flutter::EncodableValue(kEventValue), flutter::EncodableValue(title)},
    });
    EmitEvent(event);
  });

  webview_->OnSurfaceSizeChanged([this](size_t width, size_t height) {
    texture_bridge_->NotifySurfaceSizeChanged();
  });

  webview_->OnCursorChanged([this](const HCURSOR cursor) {
    const auto& name = util::GetCursorName(cursor);
    const auto event = flutter::EncodableValue(
        flutter::EncodableMap{{flutter::EncodableValue(kEventType),
                               flutter::EncodableValue("cursorChanged")},
                              {flutter::EncodableValue(kEventValue), name}});
    EmitEvent(event);
  });

  webview_->OnWebMessageReceived([this](const std::string& message) {
    const auto event = flutter::EncodableValue(
        flutter::EncodableMap{{flutter::EncodableValue(kEventType),
                               flutter::EncodableValue("webMessageReceived")},
                              {flutter::EncodableValue(kEventValue), message}});
    EmitEvent(event);
  });

  webview_->OnPermissionRequested(
      [this](const std::string& url, WebviewPermissionKind kind,
             bool is_user_initiated,
             Webview::WebviewPermissionRequestedCompleter completer) {
        OnPermissionRequested(url, kind, is_user_initiated, completer);
      });

  webview_->OnContainsFullScreenElementChanged(
      [this](bool contains_fullscreen_element) {
        const auto event = flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue(kEventType),
             flutter::EncodableValue("containsFullScreenElementChanged")},
            {flutter::EncodableValue(kEventValue),
             contains_fullscreen_element}});
        EmitEvent(event);
      });

  webview_->OnFocusChanged([this](bool focused) {
    const auto event = flutter::EncodableValue(
        flutter::EncodableMap{{flutter::EncodableValue(kEventType),
                               flutter::EncodableValue("focus")},
                              {flutter::EncodableValue(kEventValue), focused}});
    EmitEvent(event);
  });
}

void WebviewBridge::OnPermissionRequested(
    const std::string& url,
    WebviewPermissionKind permissionKind,
    bool isUserInitiated,
    Webview::WebviewPermissionRequestedCompleter completer) {
  auto args = std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
      {"url", url},
      {"isUserInitiated", isUserInitiated},
      {"permissionKind", static_cast<int>(permissionKind)}});

  method_channel_->InvokeMethod(
      "permissionRequested", std::move(args),
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          [completer](const flutter::EncodableValue* result) {
            auto allow = std::get_if<bool>(result);
            if (allow != nullptr) {
              return completer(*allow ? WebviewPermissionState::Allow
                                      : WebviewPermissionState::Deny);
            }
            completer(WebviewPermissionState::Default);
          },
          [completer](const std::string& error_code,
                      const std::string& error_message,
                      const flutter::EncodableValue* error_details) {
            completer(WebviewPermissionState::Default);
          },
          [completer]() { completer(WebviewPermissionState::Default); }));
}

void WebviewBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method_name = method_call.method_name();

  // setCursorPos: [double x, double y]
  if (method_name.compare(kMethodSetCursorPos) == 0) {
    const auto point = GetPointFromArgs(method_call.arguments());
    if (point) {
      webview_->SetCursorPos(point->first, point->second);
      return result->Success();
    }
    return result->Error(kErrorInvalidArgs);
  }

  // setPointerUpdate:
  // [int pointer, int event, double x, double y, double size, double pressure]
  if (method_name.compare(kMethodSetPointerUpdate) == 0) {
    const flutter::EncodableList* list =
        std::get_if<flutter::EncodableList>(method_call.arguments());
    if (!list || list->size() != 6) {
      return result->Error(kErrorInvalidArgs);
    }

    const auto pointer = std::get_if<int32_t>(&(*list)[0]);
    const auto event = std::get_if<int32_t>(&(*list)[1]);
    const auto x = std::get_if<double>(&(*list)[2]);
    const auto y = std::get_if<double>(&(*list)[3]);
    const auto size = std::get_if<double>(&(*list)[4]);
    const auto pressure = std::get_if<double>(&(*list)[5]);

    if (pointer && event && x && y && size && pressure) {
      webview_->SetPointerUpdate(*pointer,
                                 static_cast<WebviewPointerEventKind>(*event),
                                 *x, *y, *size, *pressure);
      return result->Success();
    }
    return result->Error(kErrorInvalidArgs);
  }

  // setScrollDelta: [double dx, double dy]
  if (method_name.compare(kMethodSetScrollDelta) == 0) {
    const auto delta = GetPointFromArgs(method_call.arguments());
    if (delta) {
      webview_->SetScrollDelta(delta->first, delta->second);
      return result->Success();
    }
    return result->Error(kErrorInvalidArgs);
  }

  // setPointerButton: {"button": int, "isDown": bool}
  if (method_name.compare(kMethodSetPointerButton) == 0) {
    const auto map =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!map) {
      return result->Error(kErrorInvalidArgs);
    }

    const auto button = map->find(flutter::EncodableValue("button"));
    const auto isDown = map->find(flutter::EncodableValue("isDown"));
    if (button != map->end() && isDown != map->end()) {
      const auto buttonValue = std::get_if<int32_t>(&button->second);
      const auto isDownValue = std::get_if<bool>(&isDown->second);
      if (buttonValue && isDownValue) {
        webview_->SetPointerButtonState(
            static_cast<WebviewPointerButton>(*buttonValue), *isDownValue);
        return result->Success();
      }
    }
    return result->Error(kErrorInvalidArgs);
  }

  // setSize: [double width, double height, double scale_factor]
  if (method_name.compare(kMethodSetSize) == 0) {
    auto size = GetPointAndScaleFactorFromArgs(method_call.arguments());
    if (size) {
      const auto [width, height, scale_factor] = size.value();

      webview_->SetSurfaceSize(static_cast<size_t>(width),
                               static_cast<size_t>(height),
                               static_cast<float>(scale_factor));

      texture_bridge_->Start();
      return result->Success();
    }
    return result->Error(kErrorInvalidArgs);
  }

  // loadUrl: string
  if (method_name.compare(kMethodLoadUrl) == 0) {
    if (const auto url = std::get_if<std::string>(method_call.arguments())) {
      webview_->LoadUrl(*url);
      return result->Success();
    }
    return result->Error(kErrorInvalidArgs);
  }

  // loadStringContent: string
  if (method_name.compare(kMethodLoadStringContent) == 0) {
    if (const auto content =
            std::get_if<std::string>(method_call.arguments())) {
      webview_->LoadStringContent(*content);
      return result->Success();
    }
    return result->Error(kErrorInvalidArgs);
  }

  // reload
  if (method_name.compare(kMethodReload) == 0) {
    if (webview_->Reload()) {
      return result->Success();
    }
    return result->Error(kMethodFailed);
  }

  // stop
  if (method_name.compare(kMethodStop) == 0) {
    if (webview_->Stop()) {
      return result->Success();
    }
    return result->Error(kMethodFailed);
  }

  // goBack
  if (method_name.compare(kMethodGoBack) == 0) {
    if (webview_->GoBack()) {
      return result->Success();
    }
    return result->Error(kMethodFailed);
  }

  // goForward
  if (method_name.compare(kMethodGoForward) == 0) {
    if (webview_->GoForward()) {
      return result->Success();
    }
    return result->Error(kMethodFailed);
  }

  // suspend
  if (method_name.compare(kMethodSuspend) == 0) {
    texture_bridge_->Stop();
    webview_->Suspend();
    return result->Success();
  }

  // resume
  if (method_name.compare(kMethodResume) == 0) {
    webview_->Resume();
    texture_bridge_->Start();
    return result->Success();
  }

  // setVirtualHostNameMapping [string hostName, string path, int accessKind]
  if (method_name.compare(kMethodSetVirtualHostNameMapping) == 0) {
    const flutter::EncodableList* list =
        std::get_if<flutter::EncodableList>(method_call.arguments());
    if (!list || list->size() != 3) {
      return result->Error(kErrorInvalidArgs);
    }

    const auto hostName = std::get_if<std::string>(&(*list)[0]);
    const auto path = std::get_if<std::string>(&(*list)[1]);
    const auto accessKind = std::get_if<int32_t>(&(*list)[2]);

    if (hostName && path && accessKind) {
      webview_->SetVirtualHostNameMapping(
          *hostName, *path,
          static_cast<WebviewHostResourceAccessKind>(*accessKind));
      return result->Success();
    }
    return result->Error(kErrorInvalidArgs);
  }

  // clearVirtualHostNameMapping: string
  if (method_name.compare(kMethodClearVirtualHostNameMapping) == 0) {
    if (const auto hostName =
            std::get_if<std::string>(method_call.arguments())) {
      if (webview_->ClearVirtualHostNameMapping(*hostName)) {
        return result->Success();
      }
    }
    return result->Error(kErrorInvalidArgs);
  }

  if (method_name.compare(kMethodAddScriptToExecuteOnDocumentCreated) == 0) {
    if (const auto script = std::get_if<std::string>(method_call.arguments())) {
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>
          shared_result = std::move(result);

      webview_->AddScriptToExecuteOnDocumentCreated(
          *script, [shared_result](bool success, const std::string& script_id) {
            if (success) {
              shared_result->Success(script_id);
            } else {
              shared_result->Error(kScriptFailed, "Executing script failed.");
            }
          });
      return;
    }
    return result->Error(kErrorInvalidArgs);
  }

  if (method_name.compare(kMethodRemoveScriptToExecuteOnDocumentCreated) == 0) {
    if (const auto script_id =
            std::get_if<std::string>(method_call.arguments())) {
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>
          shared_result = std::move(result);

      webview_->RemoveScriptToExecuteOnDocumentCreated(*script_id);
      shared_result->Success();
      return;
    }
    return result->Error(kErrorInvalidArgs);
  }

  // executeScript: string
  if (method_name.compare(kMethodExecuteScript) == 0) {
    if (const auto script = std::get_if<std::string>(method_call.arguments())) {
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>
          shared_result = std::move(result);

      webview_->ExecuteScript(
          *script,
          [shared_result](bool success, const std::string& json_result) {
            if (success) {
              shared_result->Success(json_result);
            } else {
              shared_result->Error(kScriptFailed, "Executing script failed.");
            }
          });
      return;
    }
    return result->Error(kErrorInvalidArgs);
  }

  // postWebMessage: string
  if (method_name.compare(kMethodPostWebMessage) == 0) {
    if (const auto message =
            std::get_if<std::string>(method_call.arguments())) {
      if (webview_->PostWebMessage(*message)) {
        return result->Success();
      }
      return result->Error(kErrorNotSupported, "Posting the message failed.");
    }
    return result->Error(kErrorInvalidArgs);
  }

  // setUserAgent: string
  if (method_name.compare(kMethodSetUserAgent) == 0) {
    if (const auto user_agent =
            std::get_if<std::string>(method_call.arguments())) {
      if (webview_->SetUserAgent(*user_agent)) {
        return result->Success();
      }
      return result->Error(kErrorNotSupported,
                           "Setting the user agent failed.");
    }
    return result->Error(kErrorInvalidArgs);
  }

  // setBackgroundColor: int
  if (method_name.compare(kMethodSetBackgroundColor) == 0) {
    if (const auto color = std::get_if<int32_t>(method_call.arguments())) {
      if (webview_->SetBackgroundColor(*color)) {
        return result->Success();
      }
      return result->Error(kErrorNotSupported,
                           "Setting the background color failed.");
    }
    return result->Error(kErrorInvalidArgs);
  }

  // setZoomFactor: double
  if (method_name.compare(kMethodSetZoomFactor) == 0) {
    if (const auto factor = std::get_if<double>(method_call.arguments())) {
      if (webview_->SetZoomFactor(*factor)) {
        return result->Success();
      }
      return result->Error(kErrorNotSupported,
                           "Setting the zoom factor failed.");
    }
    return result->Error(kErrorInvalidArgs);
  }

  // openDevTools
  if (method_name.compare(kMethodOpenDevTools) == 0) {
    if (webview_->OpenDevTools()) {
      return result->Success();
    }
    return result->Error(kMethodFailed);
  }

  // getCookies: string uri (empty for all cookies)
  if (method_name.compare(kMethodGetCookies) == 0) {
    if (const auto uri = std::get_if<std::string>(method_call.arguments())) {
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>
          shared_result = std::move(result);

      webview_->GetCookies(
          *uri, [shared_result](bool success,
                                std::vector<WebviewCookie> cookies) {
            if (!success) {
              return shared_result->Error(kMethodFailed,
                                          "Retrieving cookies failed.");
            }
            flutter::EncodableList list;
            list.reserve(cookies.size());
            for (const auto& cookie : cookies) {
              list.push_back(flutter::EncodableValue(flutter::EncodableMap{
                  {flutter::EncodableValue("name"),
                   flutter::EncodableValue(cookie.name)},
                  {flutter::EncodableValue("value"),
                   flutter::EncodableValue(cookie.value)},
                  {flutter::EncodableValue("domain"),
                   flutter::EncodableValue(cookie.domain)},
                  {flutter::EncodableValue("path"),
                   flutter::EncodableValue(cookie.path)},
                  {flutter::EncodableValue("expires"),
                   flutter::EncodableValue(cookie.expires)},
                  {flutter::EncodableValue("isSecure"),
                   flutter::EncodableValue(cookie.is_secure)},
                  {flutter::EncodableValue("isHttpOnly"),
                   flutter::EncodableValue(cookie.is_http_only)},
                  {flutter::EncodableValue("isSession"),
                   flutter::EncodableValue(cookie.is_session)},
                  {flutter::EncodableValue("sameSite"),
                   flutter::EncodableValue(cookie.same_site)},
              }));
            }
            shared_result->Success(flutter::EncodableValue(std::move(list)));
          });
      return;
    }
    return result->Error(kErrorInvalidArgs);
  }

  // setCookie: map (see WebviewCookie)
  if (method_name.compare(kMethodSetCookie) == 0) {
    const auto map =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!map) {
      return result->Error(kErrorInvalidArgs);
    }

    const auto get_string = [map](const char* key) -> const std::string* {
      const auto it = map->find(flutter::EncodableValue(key));
      return it != map->end() ? std::get_if<std::string>(&it->second)
                              : nullptr;
    };
    const auto get_bool = [map](const char* key) -> const bool* {
      const auto it = map->find(flutter::EncodableValue(key));
      return it != map->end() ? std::get_if<bool>(&it->second) : nullptr;
    };

    const auto name = get_string("name");
    const auto value = get_string("value");
    const auto domain = get_string("domain");
    const auto path = get_string("path");
    const auto is_secure = get_bool("isSecure");
    const auto is_http_only = get_bool("isHttpOnly");
    const auto expires_it = map->find(flutter::EncodableValue("expires"));
    const auto expires = expires_it != map->end()
                             ? std::get_if<double>(&expires_it->second)
                             : nullptr;
    const auto same_site_it = map->find(flutter::EncodableValue("sameSite"));
    const auto same_site = same_site_it != map->end()
                               ? std::get_if<int32_t>(&same_site_it->second)
                               : nullptr;

    if (name && value && domain && path && is_secure && is_http_only &&
        same_site) {
      WebviewCookie cookie;
      cookie.name = *name;
      cookie.value = *value;
      cookie.domain = *domain;
      cookie.path = *path;
      cookie.expires = expires ? *expires : -1.0;
      cookie.is_secure = *is_secure;
      cookie.is_http_only = *is_http_only;
      cookie.same_site = *same_site;
      if (webview_->SetCookie(cookie)) {
        return result->Success();
      }
      return result->Error(kMethodFailed, "Setting the cookie failed.");
    }
    return result->Error(kErrorInvalidArgs);
  }

  // deleteCookies: [string name, string uri]
  if (method_name.compare(kMethodDeleteCookies) == 0) {
    const flutter::EncodableList* list =
        std::get_if<flutter::EncodableList>(method_call.arguments());
    if (!list || list->size() != 2) {
      return result->Error(kErrorInvalidArgs);
    }
    const auto name = std::get_if<std::string>(&(*list)[0]);
    const auto uri = std::get_if<std::string>(&(*list)[1]);
    if (name && uri) {
      if (webview_->DeleteCookies(*name, *uri)) {
        return result->Success();
      }
      return result->Error(kMethodFailed, "Deleting cookies failed.");
    }
    return result->Error(kErrorInvalidArgs);
  }

  // clearCookies
  if (method_name.compare(kMethodClearCookies) == 0) {
    if (webview_->ClearCookies()) {
      return result->Success();
    }
    return result->Error(kMethodFailed);
  }

  // clearCache
  if (method_name.compare(kMethodClearCache) == 0) {
    if (webview_->ClearCache()) {
      return result->Success();
    }
    return result->Error(kMethodFailed);
  }

  // setCacheDisabled: bool
  if (method_name.compare(kMethodSetCacheDisabled) == 0) {
    if (const auto disabled = std::get_if<bool>(method_call.arguments())) {
      if (webview_->SetCacheDisabled(*disabled)) {
        return result->Success();
      }
    }
    return result->Error(kErrorInvalidArgs);
  }

  // setPopupWindowPolicy: int
  if (method_name.compare(kMethodSetPopupWindowPolicy) == 0) {
    if (const auto index = std::get_if<int32_t>(method_call.arguments())) {
      switch (*index) {
        case 1:
          webview_->SetPopupWindowPolicy(WebviewPopupWindowPolicy::Deny);
          break;
        case 2:
          webview_->SetPopupWindowPolicy(
              WebviewPopupWindowPolicy::ShowInSameWindow);
          break;
        default:
          webview_->SetPopupWindowPolicy(WebviewPopupWindowPolicy::Allow);
          break;
      }
      return result->Success();
    }
    return result->Error(kErrorInvalidArgs);
  }

  if (method_name.compare(kMethodSetFpsLimit) == 0) {
    if (const auto value = std::get_if<int32_t>(method_call.arguments())) {
      texture_bridge_->SetFpsLimit(*value == 0 ? std::nullopt
                                               : std::make_optional(*value));
      return result->Success();
    }
    return result->Error(kErrorInvalidArgs);
  }

  // moveFocus
  if (method_name.compare(kMethodMoveFocus) == 0) {
    if (webview_->MoveFocus()) {
      return result->Success();
    }
    return result->Error(kMethodFailed);
  }

  result->NotImplemented();
}
