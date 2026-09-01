#include "webview.h"

#include <wrl.h>

#include <format>
#include <iostream>

#include "util/composition.desktop.interop.h"
#include "util/string_converter.h"
#include "util/surface_geometry.h"
#include "webview_host.h"

using namespace Microsoft::WRL;

namespace {

inline void ConvertColor(COREWEBVIEW2_COLOR& webview_color, int32_t color) {
  webview_color.B = color & 0xFF;
  webview_color.G = (color >> 8) & 0xFF;
  webview_color.R = (color >> 16) & 0xFF;
  webview_color.A = (color >> 24) & 0xFF;
}

inline WebviewPermissionKind CW2PermissionKindToPermissionKind(
    COREWEBVIEW2_PERMISSION_KIND kind) {
  using k = COREWEBVIEW2_PERMISSION_KIND;
  switch (kind) {
    case k::COREWEBVIEW2_PERMISSION_KIND_MICROPHONE:
      return WebviewPermissionKind::Microphone;
    case k::COREWEBVIEW2_PERMISSION_KIND_CAMERA:
      return WebviewPermissionKind::Camera;
    case k::COREWEBVIEW2_PERMISSION_KIND_GEOLOCATION:
      return WebviewPermissionKind::GeoLocation;
    case k::COREWEBVIEW2_PERMISSION_KIND_NOTIFICATIONS:
      return WebviewPermissionKind::Notifications;
    case k::COREWEBVIEW2_PERMISSION_KIND_OTHER_SENSORS:
      return WebviewPermissionKind::OtherSensors;
    case k::COREWEBVIEW2_PERMISSION_KIND_CLIPBOARD_READ:
      return WebviewPermissionKind::ClipboardRead;
    default:
      return WebviewPermissionKind::Unknown;
  }
}

inline COREWEBVIEW2_PERMISSION_STATE WebViewPermissionStateToCW2PermissionState(
    WebviewPermissionState state) {
  using s = COREWEBVIEW2_PERMISSION_STATE;
  switch (state) {
    case WebviewPermissionState::Allow:
      return s::COREWEBVIEW2_PERMISSION_STATE_ALLOW;
    case WebviewPermissionState::Deny:
      return s::COREWEBVIEW2_PERMISSION_STATE_DENY;
    default:
      return s::COREWEBVIEW2_PERMISSION_STATE_DEFAULT;
  }
}

}  // namespace

Webview::Webview(
    wil::com_ptr<ICoreWebView2CompositionController> composition_controller,
    WebviewHost* host, HWND hwnd, HWND flutter_view_hwnd, bool owns_window,
    bool offscreen_only)
    : composition_controller_(std::move(composition_controller)),
      host_(host),
      hwnd_(hwnd),
      flutter_view_hwnd_(flutter_view_hwnd),
      owns_window_(owns_window) {
  webview_controller_ =
      composition_controller_.try_query<ICoreWebView2Controller3>();

  if (!webview_controller_ ||
      FAILED(webview_controller_->get_CoreWebView2(webview_.put()))) {
    return;
  }

  webview_controller_->put_BoundsMode(COREWEBVIEW2_BOUNDS_MODE_USE_RAW_PIXELS);
  webview_controller_->put_ShouldDetectMonitorScaleChanges(FALSE);
  webview_controller_->put_RasterizationScale(1.0);

  if (flutter_view_hwnd) {
    // Reparent the WebView2 input windows into the Flutter view's window
    // tree. WebView2 composition hosting has no keyboard injection API, so
    // the browser's hidden input window must take real Win32 focus for
    // typing to work. With the (default) message-only parent window, that
    // focus change leaves the host window's tree and deactivates it (gray
    // title bar, Flutter loses all key events). Parenting to the Flutter
    // view keeps focus changes inside one top-level tree.
    // See https://github.com/jnschulze/flutter-webview-windows/issues/230.
    webview_controller_->put_ParentWindow(flutter_view_hwnd);
  }

  if (SUCCEEDED(webview_->get_Settings(settings_.put())) && settings_) {
    settings2_ = settings_.try_query<ICoreWebView2Settings2>();

    settings_->put_IsStatusBarEnabled(FALSE);
    settings_->put_AreDefaultContextMenusEnabled(FALSE);
  }

  EnableSecurityUpdates();
  RegisterEventHandlers();

  is_valid_ = CreateSurface(host->compositor(), hwnd, offscreen_only);
}

Webview::~Webview() {
  // Drop the focus callback before closing: Close() can synchronously raise
  // LostFocus, and by destruction time the owning bridge's event sink may
  // already be gone.
  focus_changed_callback_ = nullptr;
  if (webview_controller_) {
    // Explicitly close the controller so WebView2 tears down the browser
    // windows that were reparented into the Flutter view's window tree.
    webview_controller_->Close();
  }
  if (owns_window_) {
    DestroyWindow(hwnd_);
  }
}

bool Webview::CreateSurface(
    winrt::com_ptr<ABI::Windows::UI::Composition::ICompositor> compositor,
    HWND hwnd, bool offscreen_only) {
  winrt::com_ptr<ABI::Windows::UI::Composition::IContainerVisual> root;
  if (FAILED(compositor->CreateContainerVisual(root.put()))) {
    return false;
  }

  surface_ = root.try_as<ABI::Windows::UI::Composition::IVisual>();
  assert(surface_);

  // initial size. doesn't matter as we resize the surface anyway.
  surface_->put_Size({1280, 720});
  surface_->put_IsVisible(true);

  // Create on-screen window for debugging purposes
  if (!offscreen_only) {
    window_target_ = util::TryCreateDesktopWindowTarget(compositor, hwnd);
    auto composition_target =
        window_target_
            .try_as<ABI::Windows::UI::Composition::ICompositionTarget>();
    if (composition_target) {
      composition_target->put_Root(surface_.get());
    }
  }

  winrt::com_ptr<ABI::Windows::UI::Composition::IVisual> webview_visual;
  compositor->CreateContainerVisual(
      reinterpret_cast<ABI::Windows::UI::Composition::IContainerVisual**>(
          webview_visual.put()));

  auto webview_visual2 =
      webview_visual.try_as<ABI::Windows::UI::Composition::IVisual2>();
  if (webview_visual2) {
    webview_visual2->put_RelativeSizeAdjustment({1.0f, 1.0f});
  }

  winrt::com_ptr<ABI::Windows::UI::Composition::IVisualCollection> children;
  root->get_Children(children.put());
  children->InsertAtTop(webview_visual.get());
  composition_controller_->put_RootVisualTarget(webview_visual2.get());

  webview_controller_->put_IsVisible(true);

  return true;
}

void Webview::EnableSecurityUpdates() {
  if (SUCCEEDED(webview_->CallDevToolsProtocolMethod(L"Security.enable", L"{}",
                                                     nullptr)) &&
      SUCCEEDED(webview_->GetDevToolsProtocolEventReceiver(
          L"Security.securityStateChanged",
          &devtools_protocol_event_receiver_))) {
    devtools_protocol_event_receiver_->add_DevToolsProtocolEventReceived(
        Callback<ICoreWebView2DevToolsProtocolEventReceivedEventHandler>(
            [this](ICoreWebView2* sender,
                   ICoreWebView2DevToolsProtocolEventReceivedEventArgs* args)
                -> HRESULT {
              if (devtools_protocol_event_callback_) {
                wil::unique_cotaskmem_string json_args;
                if (args->get_ParameterObjectAsJson(&json_args) == S_OK) {
                  std::string json = util::Utf8FromUtf16(json_args.get());
                  devtools_protocol_event_callback_(json.c_str());
                }
              }

              return S_OK;
            })
            .Get(),
        &event_registrations_.devtools_protocol_event_token_);
  }
}

void Webview::RegisterEventHandlers() {
  if (!webview_) {
    return;
  }

  webview_->add_ContentLoading(
      Callback<ICoreWebView2ContentLoadingEventHandler>(
          [this](ICoreWebView2* sender, IUnknown* args) -> HRESULT {
            if (loading_state_changed_callback_) {
              loading_state_changed_callback_(WebviewLoadingState::Loading);
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.content_loading_token_);

  webview_->add_NavigationCompleted(
      Callback<ICoreWebView2NavigationCompletedEventHandler>(
          [this](ICoreWebView2* sender,
                 ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
            BOOL is_success;
            args->get_IsSuccess(&is_success);
            if (!is_success && on_load_error_callback_) {
              COREWEBVIEW2_WEB_ERROR_STATUS web_error_status;
              args->get_WebErrorStatus(&web_error_status);
              on_load_error_callback_(web_error_status);
            }

            if (loading_state_changed_callback_) {
              loading_state_changed_callback_(
                  WebviewLoadingState::NavigationCompleted);
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.navigation_completed_token_);

  webview_->add_HistoryChanged(
      Callback<ICoreWebView2HistoryChangedEventHandler>(
          [this](ICoreWebView2* sender, IUnknown* args) -> HRESULT {
            if (history_changed_callback_) {
              BOOL can_go_back;
              BOOL can_go_forward;
              sender->get_CanGoBack(&can_go_back);
              sender->get_CanGoForward(&can_go_forward);
              history_changed_callback_({can_go_back, can_go_forward});
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.history_changed_token_);

  webview_->add_SourceChanged(
      Callback<ICoreWebView2SourceChangedEventHandler>(
          [this](ICoreWebView2* sender, IUnknown* args) -> HRESULT {
            wil::unique_cotaskmem_string wurl;
            if (url_changed_callback_ && webview_->get_Source(&wurl) == S_OK) {
              std::string url = util::Utf8FromUtf16(wurl.get());
              url_changed_callback_(url);
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.source_changed_token_);

  webview_->add_DocumentTitleChanged(
      Callback<ICoreWebView2DocumentTitleChangedEventHandler>(
          [this](ICoreWebView2* sender, IUnknown* args) -> HRESULT {
            wil::unique_cotaskmem_string wtitle;
            if (document_title_changed_callback_ &&
                webview_->get_DocumentTitle(&wtitle) == S_OK) {
              std::string title = util::Utf8FromUtf16(wtitle.get());
              document_title_changed_callback_(title);
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.document_title_changed_token_);

  composition_controller_->add_CursorChanged(
      Callback<ICoreWebView2CursorChangedEventHandler>(
          [this](ICoreWebView2CompositionController* sender,
                 IUnknown* args) -> HRESULT {
            HCURSOR cursor;
            if (cursor_changed_callback_ &&
                sender->get_Cursor(&cursor) == S_OK) {
              cursor_changed_callback_(cursor);
            }
            return S_OK;
          })
          .Get(),
      &event_registrations_.cursor_changed_token_);

  webview_controller_->add_GotFocus(
      Callback<ICoreWebView2FocusChangedEventHandler>(
          [this](ICoreWebView2Controller* sender, IUnknown* args) -> HRESULT {
            if (focus_changed_callback_) {
              focus_changed_callback_(true);
            }
            return S_OK;
          })
          .Get(),
      &event_registrations_.got_focus_token_);

  webview_controller_->add_LostFocus(
      Callback<ICoreWebView2FocusChangedEventHandler>(
          [this](ICoreWebView2Controller* sender, IUnknown* args) -> HRESULT {
            if (focus_changed_callback_) {
              focus_changed_callback_(false);
            }
            return S_OK;
          })
          .Get(),
      &event_registrations_.lost_focus_token_);

  if (flutter_view_hwnd_) {
    // When Tab traversal moves past the page's last focusable element (or
    // before its first), return Win32 keyboard focus to the Flutter view so
    // focus leaves the webview instead of cycling inside the page forever.
    webview_controller_->add_MoveFocusRequested(
        Callback<ICoreWebView2MoveFocusRequestedEventHandler>(
            [this](ICoreWebView2Controller* sender,
                   ICoreWebView2MoveFocusRequestedEventArgs* args) -> HRESULT {
              SetFocus(flutter_view_hwnd_);
              args->put_Handled(TRUE);
              return S_OK;
            })
            .Get(),
        &event_registrations_.move_focus_requested_token_);
  }

  webview_->add_WebMessageReceived(
      Callback<ICoreWebView2WebMessageReceivedEventHandler>(
          [this](ICoreWebView2* sender,
                 ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
            wil::unique_cotaskmem_string wmessage;
            if (web_message_received_callback_ &&
                args->get_WebMessageAsJson(&wmessage) == S_OK) {
              const std::string message = util::Utf8FromUtf16(wmessage.get());
              web_message_received_callback_(message);
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.web_message_received_token_);

  webview_->add_PermissionRequested(
      Callback<ICoreWebView2PermissionRequestedEventHandler>(
          [this](ICoreWebView2* sender,
                 ICoreWebView2PermissionRequestedEventArgs* args) -> HRESULT {
            if (!permission_requested_callback_) {
              return S_OK;
            }

            wil::unique_cotaskmem_string wuri;
            COREWEBVIEW2_PERMISSION_KIND kind =
                COREWEBVIEW2_PERMISSION_KIND_UNKNOWN_PERMISSION;
            BOOL is_user_initiated = false;

            if (args->get_Uri(&wuri) == S_OK &&
                args->get_PermissionKind(&kind) == S_OK &&
                args->get_IsUserInitiated(&is_user_initiated) == S_OK) {
              wil::com_ptr<ICoreWebView2Deferral> deferral;
              args->GetDeferral(deferral.put());

              const std::string uri = util::Utf8FromUtf16(wuri.get());
              permission_requested_callback_(
                  uri, CW2PermissionKindToPermissionKind(kind),
                  is_user_initiated == TRUE,
                  // The event args are only borrowed for the duration of this
                  // handler, but the completer runs after an async round trip
                  // to Dart; keep a real reference (AddRef) on them.
                  [deferral = std::move(deferral),
                   args = wil::com_ptr<ICoreWebView2PermissionRequestedEventArgs>(
                       args)](WebviewPermissionState state) {
                    args->put_State(
                        WebViewPermissionStateToCW2PermissionState(state));
                    deferral->Complete();
                  });
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.permission_requested_token_);

  webview_->add_NewWindowRequested(
      Callback<ICoreWebView2NewWindowRequestedEventHandler>(
          [this](ICoreWebView2* sender,
                 ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT {
            switch (popup_window_policy_) {
              case WebviewPopupWindowPolicy::Deny:
                args->put_Handled(TRUE);
                break;
              case WebviewPopupWindowPolicy::ShowInSameWindow:
                args->put_NewWindow(webview_.get());
                args->put_Handled(TRUE);
                break;
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.new_windows_requested_token_);

  webview_->add_ContainsFullScreenElementChanged(
      Callback<ICoreWebView2ContainsFullScreenElementChangedEventHandler>(
          [this](ICoreWebView2* sender, IUnknown* args) -> HRESULT {
            BOOL flag = FALSE;
            if (contains_fullscreen_element_changed_callback_ &&
                SUCCEEDED(sender->get_ContainsFullScreenElement(&flag))) {
              contains_fullscreen_element_changed_callback_(flag);
            }
            return S_OK;
          })
          .Get(),
      &event_registrations_.contains_fullscreen_element_changed_token_);

  auto webview24 = webview_.try_query<ICoreWebView2_4>();
  if (webview24) {
    webview24->add_DownloadStarting(
        Callback<ICoreWebView2DownloadStartingEventHandler>(
            [this](ICoreWebView2* sender,
                   ICoreWebView2DownloadStartingEventArgs* args) -> HRESULT {
              // Everything below runs synchronously, so no deferral is taken;
              // taking one without completing it would leave the event pending.
              args->put_Handled(TRUE);

              wil::com_ptr<ICoreWebView2DownloadOperation> download;
              if (FAILED(args->get_DownloadOperation(download.put())) ||
                  !download) {
                return S_OK;
              }

              INT64 totalBytesToReceive = 0;
              download->get_TotalBytesToReceive(&totalBytesToReceive);

              wil::unique_cotaskmem_string uri;
              download->get_Uri(&uri);

              wil::unique_cotaskmem_string mimeType;
              download->get_MimeType(&mimeType);

              wil::unique_cotaskmem_string contentDisposition;
              download->get_ContentDisposition(&contentDisposition);

              wil::unique_cotaskmem_string resultFilePath;
              args->get_ResultFilePath(&resultFilePath);

              args->put_ResultFilePath(resultFilePath.get());
              UpdateDownloadProgress(download.get());

              if (download_event_callback_) {
                download_event_callback_(
                    {WebviewDownloadEventKind::DownloadStarted,
                     util::Utf8FromUtf16(uri.get()),
                     util::Utf8FromUtf16(resultFilePath.get()), 0,
                     totalBytesToReceive});
              }

              return S_OK;
            })
            .Get(),
        &event_registrations_.download_starting_token_);
  }
}

void Webview::SetSurfaceSize(const util::SurfaceGeometry& geometry) {
  if (!IsValid() || !surface_ || geometry.width == 0 ||
      geometry.height == 0) {
    return;
  }

  const RECT bounds = util::SurfaceBounds(geometry);
  // Only an extent change touches the composition surface and the
  // rasterization scale and, through the size-changed callback, recreates
  // the texture's frame pool. A webview that merely moved, which happens
  // every frame while it scrolls or animates, only needs its Bounds origin
  // updated so WebView2 keeps anchoring popups to it.
  const bool extent_changed = !util::SameExtent(geometry, surface_geometry_);
  const bool origin_changed =
      bounds.left != bounds_.left || bounds.top != bounds_.top;
  if (!extent_changed && !origin_changed) {
    return;
  }
  surface_geometry_ = geometry;
  bounds_ = bounds;

  if (extent_changed) {
    const auto scaled_width = geometry.width * geometry.scale_factor;
    const auto scaled_height = geometry.height * geometry.scale_factor;
    surface_->put_Size({scaled_width, scaled_height});
    webview_controller_->put_RasterizationScale(geometry.scale_factor);
  }
  if (webview_controller_->put_Bounds(bounds) != S_OK) {
    std::cerr << "Setting webview bounds failed." << std::endl;
  }

  if (extent_changed && surface_size_changed_callback_) {
    surface_size_changed_callback_(geometry.width, geometry.height);
  }
}

void Webview::NotifyParentWindowMoved() {
  if (!IsValid()) {
    return;
  }
  webview_controller_->NotifyParentWindowPositionChanged();
}

bool Webview::OpenDevTools() {
  if (!IsValid()) {
    return false;
  }
  webview_->OpenDevToolsWindow();
  return true;
}

void Webview::GetCookies(const std::string& uri, GetCookiesCallback callback) {
  wil::com_ptr<ICoreWebView2CookieManager> cookie_manager;
  auto webview2 = webview_ ? webview_.try_query<ICoreWebView2_2>() : nullptr;
  if (!IsValid() || !webview2 ||
      FAILED(webview2->get_CookieManager(cookie_manager.put())) ||
      !cookie_manager) {
    return callback(false, {});
  }

  const auto wuri = util::Utf16FromUtf8(uri);
  const auto hr = cookie_manager->GetCookies(
      uri.empty() ? nullptr : wuri.c_str(),
      Callback<ICoreWebView2GetCookiesCompletedHandler>(
          [callback](HRESULT result,
                     ICoreWebView2CookieList* cookie_list) -> HRESULT {
            if (FAILED(result) || !cookie_list) {
              callback(false, {});
              return S_OK;
            }

            UINT count = 0;
            cookie_list->get_Count(&count);
            std::vector<WebviewCookie> cookies;
            cookies.reserve(count);
            for (UINT i = 0; i < count; ++i) {
              wil::com_ptr<ICoreWebView2Cookie> cookie;
              if (FAILED(cookie_list->GetValueAtIndex(i, cookie.put())) ||
                  !cookie) {
                continue;
              }
              WebviewCookie entry;
              wil::unique_cotaskmem_string name, value, domain, path;
              if (SUCCEEDED(cookie->get_Name(name.put()))) {
                entry.name = util::Utf8FromUtf16(name.get());
              }
              if (SUCCEEDED(cookie->get_Value(value.put()))) {
                entry.value = util::Utf8FromUtf16(value.get());
              }
              if (SUCCEEDED(cookie->get_Domain(domain.put()))) {
                entry.domain = util::Utf8FromUtf16(domain.get());
              }
              if (SUCCEEDED(cookie->get_Path(path.put()))) {
                entry.path = util::Utf8FromUtf16(path.get());
              }
              cookie->get_Expires(&entry.expires);
              BOOL flag = FALSE;
              if (SUCCEEDED(cookie->get_IsSecure(&flag))) {
                entry.is_secure = flag == TRUE;
              }
              flag = FALSE;
              if (SUCCEEDED(cookie->get_IsHttpOnly(&flag))) {
                entry.is_http_only = flag == TRUE;
              }
              flag = FALSE;
              if (SUCCEEDED(cookie->get_IsSession(&flag))) {
                entry.is_session = flag == TRUE;
              }
              COREWEBVIEW2_COOKIE_SAME_SITE_KIND same_site =
                  COREWEBVIEW2_COOKIE_SAME_SITE_KIND_LAX;
              if (SUCCEEDED(cookie->get_SameSite(&same_site))) {
                entry.same_site = static_cast<int>(same_site);
              }
              cookies.push_back(std::move(entry));
            }

            callback(true, std::move(cookies));
            return S_OK;
          })
          .Get());

  if (FAILED(hr)) {
    callback(false, {});
  }
}

bool Webview::SetCookie(const WebviewCookie& cookie) {
  wil::com_ptr<ICoreWebView2CookieManager> cookie_manager;
  auto webview2 = webview_ ? webview_.try_query<ICoreWebView2_2>() : nullptr;
  if (!IsValid() || !webview2 ||
      FAILED(webview2->get_CookieManager(cookie_manager.put())) ||
      !cookie_manager) {
    return false;
  }

  wil::com_ptr<ICoreWebView2Cookie> native_cookie;
  if (FAILED(cookie_manager->CreateCookie(
          util::Utf16FromUtf8(cookie.name).c_str(),
          util::Utf16FromUtf8(cookie.value).c_str(),
          util::Utf16FromUtf8(cookie.domain).c_str(),
          util::Utf16FromUtf8(cookie.path).c_str(), native_cookie.put())) ||
      !native_cookie) {
    return false;
  }

  // A negative expiry marks a session cookie, which is the created cookie's
  // default; only a concrete expiry needs to be written.
  if (cookie.expires >= 0) {
    native_cookie->put_Expires(cookie.expires);
  }
  native_cookie->put_IsSecure(cookie.is_secure ? TRUE : FALSE);
  native_cookie->put_IsHttpOnly(cookie.is_http_only ? TRUE : FALSE);
  native_cookie->put_SameSite(
      static_cast<COREWEBVIEW2_COOKIE_SAME_SITE_KIND>(cookie.same_site));

  return SUCCEEDED(cookie_manager->AddOrUpdateCookie(native_cookie.get()));
}

bool Webview::DeleteCookies(const std::string& name, const std::string& uri) {
  wil::com_ptr<ICoreWebView2CookieManager> cookie_manager;
  auto webview2 = webview_ ? webview_.try_query<ICoreWebView2_2>() : nullptr;
  if (!IsValid() || !webview2 ||
      FAILED(webview2->get_CookieManager(cookie_manager.put())) ||
      !cookie_manager) {
    return false;
  }

  const auto wname = util::Utf16FromUtf8(name);
  const auto wuri = util::Utf16FromUtf8(uri);
  return SUCCEEDED(cookie_manager->DeleteCookies(
      wname.c_str(), uri.empty() ? nullptr : wuri.c_str()));
}

bool Webview::ClearCookies() {
  if (!IsValid()) {
    return false;
  }
  return webview_->CallDevToolsProtocolMethod(L"Network.clearBrowserCookies",
                                              L"{}", nullptr) == S_OK;
}

bool Webview::ClearCache() {
  if (!IsValid()) {
    return false;
  }
  return webview_->CallDevToolsProtocolMethod(L"Network.clearBrowserCache",
                                              L"{}", nullptr) == S_OK;
}

bool Webview::SetCacheDisabled(bool disabled) {
  if (!IsValid()) {
    return false;
  }
  std::string json = std::format("{{\"disableCache\":{}}}", disabled);
  return webview_->CallDevToolsProtocolMethod(L"Network.setCacheDisabled",
                                              util::Utf16FromUtf8(json).c_str(),
                                              nullptr) == S_OK;
}

void Webview::SetPopupWindowPolicy(WebviewPopupWindowPolicy policy) {
  popup_window_policy_ = policy;
}

bool Webview::SetDefaultContextMenusEnabled(bool enabled) {
  if (!settings_) {
    return false;
  }
  return SUCCEEDED(
      settings_->put_AreDefaultContextMenusEnabled(enabled ? TRUE : FALSE));
}

bool Webview::SetUserAgent(const std::string& user_agent) {
  if (settings2_) {
    return settings2_->put_UserAgent(util::Utf16FromUtf8(user_agent).c_str()) ==
           S_OK;
  }
  return false;
}

bool Webview::SetBackgroundColor(int32_t color) {
  if (!IsValid()) {
    return false;
  }

  COREWEBVIEW2_COLOR webview_color;
  ConvertColor(webview_color, color);

  // Semi-transparent backgrounds are not supported.
  // Valid alpha values are 0 or 255.
  if (webview_color.A > 0) {
    webview_color.A = 0xFF;
  }

  return webview_controller_->put_DefaultBackgroundColor(webview_color) == S_OK;
}

bool Webview::SetZoomFactor(double factor) {
  if (!IsValid()) {
    return false;
  }
  return webview_controller_->put_ZoomFactor(factor) == S_OK;
}

void Webview::SetCursorPos(double x, double y) {
  if (!IsValid()) {
    return;
  }

  POINT point;
  point.x = static_cast<LONG>(x * surface_geometry_.scale_factor);
  point.y = static_cast<LONG>(y * surface_geometry_.scale_factor);
  last_cursor_pos_ = point;

  // https://docs.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2?view=webview2-1.0.774.44
  composition_controller_->SendMouseInput(
      COREWEBVIEW2_MOUSE_EVENT_KIND::COREWEBVIEW2_MOUSE_EVENT_KIND_MOVE,
      virtual_keys_.state(), 0, point);
}

void Webview::SetPointerUpdate(int32_t pointer,
                               WebviewPointerEventKind eventKind, double x,
                               double y, double size, double pressure) {
  if (!IsValid()) {
    return;
  }

  COREWEBVIEW2_POINTER_EVENT_KIND event =
      COREWEBVIEW2_POINTER_EVENT_KIND_UPDATE;
  UINT32 pointerFlags = POINTER_FLAG_NONE;
  switch (eventKind) {
    case WebviewPointerEventKind::Activate:
      event = COREWEBVIEW2_POINTER_EVENT_KIND_ACTIVATE;
      break;
    case WebviewPointerEventKind::Down:
      event = COREWEBVIEW2_POINTER_EVENT_KIND_DOWN;
      pointerFlags =
          POINTER_FLAG_DOWN | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT;
      break;
    case WebviewPointerEventKind::Enter:
      event = COREWEBVIEW2_POINTER_EVENT_KIND_ENTER;
      break;
    case WebviewPointerEventKind::Leave:
      event = COREWEBVIEW2_POINTER_EVENT_KIND_LEAVE;
      break;
    case WebviewPointerEventKind::Up:
      event = COREWEBVIEW2_POINTER_EVENT_KIND_UP;
      pointerFlags = POINTER_FLAG_UP;
      break;
    case WebviewPointerEventKind::Update:
      event = COREWEBVIEW2_POINTER_EVENT_KIND_UPDATE;
      pointerFlags =
          POINTER_FLAG_UPDATE | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT;
      break;
  }

  POINT point;
  point.x = static_cast<LONG>(x * surface_geometry_.scale_factor);
  point.y = static_cast<LONG>(y * surface_geometry_.scale_factor);

  RECT rect;
  rect.left = point.x - 2;
  rect.right = point.x + 2;
  rect.top = point.y - 2;
  rect.bottom = point.y + 2;

  host_->CreateWebViewPointerInfo(
      [this, pointer, event, pointerFlags, point, rect, pressure](
          wil::com_ptr<ICoreWebView2PointerInfo> pointerInfo,
          std::unique_ptr<WebviewCreationError> error) {
        if (pointerInfo) {
          ICoreWebView2PointerInfo* pInfo = pointerInfo.get();
          pInfo->put_PointerId(pointer);
          pInfo->put_PointerKind(PT_TOUCH);
          pInfo->put_PointerFlags(pointerFlags);
          pInfo->put_TouchFlags(TOUCH_FLAG_NONE);
          pInfo->put_TouchMask(TOUCH_MASK_CONTACTAREA | TOUCH_MASK_PRESSURE);
          pInfo->put_TouchPressure(
              std::clamp((UINT32)(pressure == 0.0 ? 1024 : 1024 * pressure),
                         (UINT32)0, (UINT32)1024));
          pInfo->put_PixelLocationRaw(point);
          pInfo->put_TouchContactRaw(rect);
          composition_controller_->SendPointerInput(event, pInfo);
        }
      });
}

void Webview::SetPointerButtonState(WebviewPointerButton button, bool is_down) {
  if (!IsValid()) {
    return;
  }

  COREWEBVIEW2_MOUSE_EVENT_KIND kind;
  switch (button) {
    case WebviewPointerButton::Primary:
      virtual_keys_.set_isLeftButtonDown(is_down);
      kind = is_down ? COREWEBVIEW2_MOUSE_EVENT_KIND_LEFT_BUTTON_DOWN
                     : COREWEBVIEW2_MOUSE_EVENT_KIND_LEFT_BUTTON_UP;
      break;
    case WebviewPointerButton::Secondary:
      virtual_keys_.set_isRightButtonDown(is_down);
      kind = is_down ? COREWEBVIEW2_MOUSE_EVENT_KIND_RIGHT_BUTTON_DOWN
                     : COREWEBVIEW2_MOUSE_EVENT_KIND_RIGHT_BUTTON_UP;
      break;
    case WebviewPointerButton::Tertiary:
      virtual_keys_.set_isMiddleButtonDown(is_down);
      kind = is_down ? COREWEBVIEW2_MOUSE_EVENT_KIND_MIDDLE_BUTTON_DOWN
                     : COREWEBVIEW2_MOUSE_EVENT_KIND_MIDDLE_BUTTON_UP;
      break;
    default:
      kind = static_cast<COREWEBVIEW2_MOUSE_EVENT_KIND>(0);
  }

  composition_controller_->SendMouseInput(kind, virtual_keys_.state(), 0,
                                          last_cursor_pos_);
}

void Webview::SendScroll(double delta, bool horizontal) {
  // clang-format off
  //
  // TODO:
  // Using a fixed value here is certainly wrong. Flutter's calculation in flutter_window.cc
  // needs to be inverted to get back the "native" value. See
  // - https://github.com/flutter/engine/blob/82c1dfcf588c2669ca391134910d634ca31fddf1/shell/platform/windows/flutter_window.cc#L416-L426
  // Related:
  // - https://source.chromium.org/chromium/chromium/src/+/main:ui/events/blink/web_input_event_builders_win.cc
  // - https://github.com/flutter/flutter/issues/107248
  //
  // clang-format on
  constexpr auto kScrollMultiplier = 1.5;

  auto offset = static_cast<short>(delta * kScrollMultiplier);

  if (horizontal) {
    composition_controller_->SendMouseInput(
        COREWEBVIEW2_MOUSE_EVENT_KIND_HORIZONTAL_WHEEL, virtual_keys_.state(),
        offset, last_cursor_pos_);
  } else {
    composition_controller_->SendMouseInput(COREWEBVIEW2_MOUSE_EVENT_KIND_WHEEL,
                                            virtual_keys_.state(), offset,
                                            last_cursor_pos_);
  }
}

void Webview::SetScrollDelta(double delta_x, double delta_y) {
  if (!IsValid()) {
    return;
  }

  if (delta_x != 0.0) {
    SendScroll(delta_x, true);
  }
  if (delta_y != 0.0) {
    SendScroll(delta_y, false);
  }
}

void Webview::LoadUrl(const std::string& url) {
  if (IsValid()) {
    webview_->Navigate(util::Utf16FromUtf8(url).c_str());
  }
}

void Webview::LoadStringContent(const std::string& content) {
  if (IsValid()) {
    webview_->NavigateToString(util::Utf16FromUtf8(content).c_str());
  }
}

bool Webview::Stop() {
  if (!IsValid()) {
    return false;
  }
  return SUCCEEDED(webview_->CallDevToolsProtocolMethod(L"Page.stopLoading",
                                                        L"{}", nullptr));
}

bool Webview::Reload() {
  if (!IsValid()) {
    return false;
  }
  return SUCCEEDED(webview_->Reload());
}

bool Webview::GoBack() {
  if (!IsValid()) {
    return false;
  }
  return SUCCEEDED(webview_->GoBack());
}

bool Webview::GoForward() {
  if (!IsValid()) {
    return false;
  }
  return SUCCEEDED(webview_->GoForward());
}

void Webview::AddScriptToExecuteOnDocumentCreated(
    const std::string& script,
    AddScriptToExecuteOnDocumentCreatedCallback callback) {
  if (IsValid()) {
    if (SUCCEEDED(webview_->AddScriptToExecuteOnDocumentCreated(
            util::Utf16FromUtf8(script).c_str(),
            Callback<
                ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>(
                [callback](HRESULT result, LPCWSTR wsid) -> HRESULT {
                  std::string sid = util::Utf8FromUtf16(wsid);
                  callback(SUCCEEDED(result), sid);
                  return S_OK;
                })
                .Get()))) {
      return;
    }
  }

  callback(false, std::string());
}

void Webview::RemoveScriptToExecuteOnDocumentCreated(
    const std::string& script_id) {
  if (IsValid()) {
    webview_->RemoveScriptToExecuteOnDocumentCreated(
        util::Utf16FromUtf8(script_id).c_str());
  }
}

void Webview::ExecuteScript(const std::string& script,
                            ScriptExecutedCallback callback) {
  if (IsValid()) {
    if (SUCCEEDED(webview_->ExecuteScript(
            util::Utf16FromUtf8(script).c_str(),
            Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
                [callback](HRESULT result, LPCWSTR json_result_object) {
                  callback(SUCCEEDED(result),
                           util::Utf8FromUtf16(json_result_object));
                  return S_OK;
                })
                .Get()))) {
      return;
    }
  }

  callback(false, std::string());
}

bool Webview::PostWebMessage(const std::string& json) {
  if (!IsValid()) {
    return false;
  }
  return webview_->PostWebMessageAsJson(util::Utf16FromUtf8(json).c_str()) ==
         S_OK;
}

bool Webview::Suspend() {
  if (!IsValid()) {
    return false;
  }

  auto webview = webview_.try_query<ICoreWebView2_3>();
  if (!webview) {
    return false;
  }

  webview_controller_->put_IsVisible(false);
  return webview->TrySuspend(
             Callback<ICoreWebView2TrySuspendCompletedHandler>(
                 [](HRESULT error_code, BOOL is_successful) -> HRESULT {
                   return S_OK;
                 })
                 .Get()) == S_OK;
}

bool Webview::Resume() {
  if (!IsValid()) {
    return false;
  }

  auto webview = webview_.try_query<ICoreWebView2_3>();
  if (!webview) {
    return false;
  }
  return webview->Resume() == S_OK &&
         webview_controller_->put_IsVisible(true) == S_OK;
}

bool Webview::MoveFocus() {
  if (!IsValid()) {
    return false;
  }
  return webview_controller_->MoveFocus(
             COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC) == S_OK;
}

bool Webview::SetVirtualHostNameMapping(
    const std::string& hostName, const std::string& path,
    WebviewHostResourceAccessKind accessKind) {
  if (!IsValid()) {
    return false;
  }

  auto webview = webview_.try_query<ICoreWebView2_3>();
  if (!webview) {
    return false;
  }

  COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND accessKindIntValue =
      COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY;
  switch (accessKind) {
    case WebviewHostResourceAccessKind::Allow:
      accessKindIntValue = COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW;
      break;
    case WebviewHostResourceAccessKind::DenyCors:
      accessKindIntValue = COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS;
      break;
    case WebviewHostResourceAccessKind::Deny:
      accessKindIntValue = COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY;
      break;
  }

  return SUCCEEDED(webview->SetVirtualHostNameToFolderMapping(
      util::Utf16FromUtf8(hostName).c_str(), util::Utf16FromUtf8(path).c_str(),
      accessKindIntValue));
}

bool Webview::ClearVirtualHostNameMapping(const std::string& hostName) {
  if (!IsValid()) {
    return false;
  }

  auto webview = webview_.try_query<ICoreWebView2_3>();
  if (!webview) {
    return false;
  }

  return SUCCEEDED(webview->ClearVirtualHostNameToFolderMapping(
      util::Utf16FromUtf8(hostName).c_str()));
}

void Webview::UpdateDownloadProgress(ICoreWebView2DownloadOperation* download) {
  download->add_BytesReceivedChanged(
      Callback<ICoreWebView2BytesReceivedChangedEventHandler>(
          [this](ICoreWebView2DownloadOperation* download,
                 IUnknown* args) -> HRESULT {
            if (download_event_callback_) {
              INT64 recvd = 0;
              download->get_BytesReceived(&recvd);
              INT64 total = 0;
              download->get_TotalBytesToReceive(&total);

              wil::unique_cotaskmem_string uri;
              download->get_Uri(&uri);
              wil::unique_cotaskmem_string resultFilePath;
              download->get_ResultFilePath(&resultFilePath);
              download_event_callback_(
                  {WebviewDownloadEventKind::DownloadProgress,
                   util::Utf8FromUtf16(uri.get()),
                   util::Utf8FromUtf16(resultFilePath.get()), recvd, total});
            }
            return S_OK;
          })
          .Get(),
      &event_registrations_.download_bytes_received_token_);

  download->add_StateChanged(
      Callback<ICoreWebView2StateChangedEventHandler>(
          [this](ICoreWebView2DownloadOperation* download,
                 IUnknown* args) -> HRESULT {
            COREWEBVIEW2_DOWNLOAD_STATE state;
            download->get_State(&state);
            switch (state) {
              case COREWEBVIEW2_DOWNLOAD_STATE_IN_PROGRESS:
                break;
              case COREWEBVIEW2_DOWNLOAD_STATE_INTERRUPTED:
                // Here developer can take different actions based on
                // `download->InterruptReason`. For example, show an error
                // message to the end user.
                break;
              case COREWEBVIEW2_DOWNLOAD_STATE_COMPLETED:
                if (download_event_callback_) {
                  wil::unique_cotaskmem_string uri;
                  download->get_Uri(&uri);
                  wil::unique_cotaskmem_string resultFilePath;
                  download->get_ResultFilePath(&resultFilePath);
                  INT64 recvd = 0;
                  download->get_BytesReceived(&recvd);
                  INT64 total = 0;
                  download->get_TotalBytesToReceive(&total);
                  download_event_callback_(
                      {WebviewDownloadEventKind::DownloadCompleted,
                       util::Utf8FromUtf16(uri.get()),
                       util::Utf8FromUtf16(resultFilePath.get()), recvd,
                       total});
                }
                break;
            }
            return S_OK;
          })
          .Get(),
      &event_registrations_.download_state_changed_token_);
}