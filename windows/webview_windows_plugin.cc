#include "include/webview_flutter_windows/webview_windows_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <wil/resource.h>
#include <windows.h>

#include <memory>
#include <string>
#include <unordered_map>

#include "util/string_converter.h"
#include "webview_bridge.h"
#include "webview_host.h"
#include "webview_platform.h"

#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3d11.lib")

namespace {

constexpr auto kMethodInitialize = "initialize";
constexpr auto kMethodDispose = "dispose";
constexpr auto kMethodInitializeEnvironment = "initializeEnvironment";
constexpr auto kMethodGetWebViewVersion = "getWebViewVersion";
constexpr auto kMethodReclaimFocus = "reclaimFocus";

constexpr auto kErrorCodeInvalidId = "invalid_id";
constexpr auto kErrorCodeInvalidArguments = "invalid_arguments";
constexpr auto kErrorCodeEnvironmentCreationFailed =
    "environment_creation_failed";
constexpr auto kErrorCodeEnvironmentAlreadyInitialized =
    "environment_already_initialized";
constexpr auto kErrorCodeWebviewCreationFailed = "webview_creation_failed";
constexpr auto kErrorUnsupportedPlatform = "unsupported_platform";

template <typename T>
std::optional<T> GetOptionalValue(const flutter::EncodableMap& map,
                                  const std::string& key) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end()) {
    const auto val = std::get_if<T>(&it->second);
    if (val) {
      return *val;
    }
  }
  return std::nullopt;
}

class WebviewWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  WebviewWindowsPlugin(flutter::PluginRegistrarWindows* registrar);

  virtual ~WebviewWindowsPlugin();

 private:
  // The options initializeEnvironment was last called with. They outlive the
  // environment itself so that an environment recreated for a later webview
  // (after the previous one was released) is configured identically.
  struct EnvironmentOptions {
    std::optional<std::wstring> user_data_path;
    std::optional<std::wstring> browser_exe_path;
    std::optional<std::string> additional_arguments;
  };

  std::unique_ptr<WebviewPlatform> platform_;
  std::unique_ptr<WebviewHost> webview_host_;
  EnvironmentOptions environment_options_{};
  std::unordered_map<int64_t, std::unique_ptr<WebviewBridge>> instances_;
  // Creations whose async completion is still outstanding. The environment
  // must not be released while any of these exist: the completion handler
  // still runs on the host.
  int pending_creations_ = 0;

  WNDCLASS window_class_ = {};
  flutter::PluginRegistrarWindows* registrar_;
  flutter::TextureRegistrar* textures_;
  flutter::BinaryMessenger* messenger_;

  bool InitPlatform();

  // Returns the HWND of the Flutter view, or nullptr if unavailable.
  HWND GetFlutterViewHwnd();

  void CreateWebviewInstance(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>);
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

// static
void WebviewWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "io.jns.webview.win",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<WebviewWindowsPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

WebviewWindowsPlugin::WebviewWindowsPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar),
      textures_(registrar->texture_registrar()),
      messenger_(registrar->messenger()) {
  window_class_.lpszClassName = L"FlutterWebviewMessage";
  window_class_.lpfnWndProc = &DefWindowProc;
  window_class_.hInstance = GetModuleHandle(nullptr);
  RegisterClass(&window_class_);
}

WebviewWindowsPlugin::~WebviewWindowsPlugin() {
  instances_.clear();
  UnregisterClass(window_class_.lpszClassName, nullptr);
}

void WebviewWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare(kMethodInitializeEnvironment) == 0) {
    // The environment can be (re)configured whenever no webviews are alive:
    // it is released when the last instance is disposed, so a later call can
    // legitimately set up a different configuration.
    if (!instances_.empty() || pending_creations_ > 0) {
      return result->Error(
          kErrorCodeEnvironmentAlreadyInitialized,
          "The webview environment cannot be configured while webviews "
          "exist. Dispose all WebviewControllers first.");
    }

    if (!InitPlatform()) {
      return result->Error(kErrorUnsupportedPlatform,
                           "The platform is not supported");
    }

    const auto map =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!map) {
      return result->Error(kErrorCodeInvalidArguments,
                           "initializeEnvironment expects a map.");
    }

    EnvironmentOptions options;
    std::optional<std::string> browser_exe_path =
        GetOptionalValue<std::string>(*map, "browserExePath");
    if (browser_exe_path) {
      options.browser_exe_path = util::Utf16FromUtf8(*browser_exe_path);
    }

    std::optional<std::string> user_data_path =
        GetOptionalValue<std::string>(*map, "userDataPath");
    if (user_data_path) {
      options.user_data_path = util::Utf16FromUtf8(*user_data_path);
    } else {
      options.user_data_path = platform_->GetDefaultDataDirectory();
    }

    options.additional_arguments =
        GetOptionalValue<std::string>(*map, "additionalArguments");

    webview_host_ = nullptr;
    auto host = WebviewHost::Create(platform_.get(), options.user_data_path,
                                    options.browser_exe_path,
                                    options.additional_arguments);
    if (!host) {
      return result->Error(kErrorCodeEnvironmentCreationFailed);
    }

    environment_options_ = std::move(options);
    webview_host_ = std::move(host);
    return result->Success();
  }

  if (method_call.method_name().compare(kMethodGetWebViewVersion) == 0) {
    wil::unique_cotaskmem_string version_info;
    auto hr = GetAvailableCoreWebView2BrowserVersionString(
        nullptr, version_info.put());
    if (SUCCEEDED(hr) && version_info != nullptr) {
      return result->Success(
          flutter::EncodableValue(util::Utf8FromUtf16(version_info.get())));
    } else {
      return result->Success();
    }
  }

  if (method_call.method_name().compare(kMethodReclaimFocus) == 0) {
    // Moves Win32 keyboard focus back to the Flutter view. This is invoked
    // by the Dart side whenever the user clicks outside of any webview while
    // a webview holds native focus, restoring Flutter's keyboard handling
    // without a window activation round trip.
    auto view_hwnd = GetFlutterViewHwnd();
    if (view_hwnd) {
      SetFocus(view_hwnd);
    }
    return result->Success(flutter::EncodableValue(view_hwnd != nullptr));
  }

  if (method_call.method_name().compare(kMethodInitialize) == 0) {
    return CreateWebviewInstance(std::move(result));
  }

  if (method_call.method_name().compare(kMethodDispose) == 0) {
    // The standard codec encodes a Dart int as int32 when it fits, so the
    // texture id must be read size-agnostically. Matching on int64 alone
    // would silently fail to dispose instances with small ids.
    const auto texture_id = method_call.arguments()
                                ? method_call.arguments()->TryGetLongValue()
                                : std::nullopt;
    if (texture_id.has_value()) {
      const auto it = instances_.find(*texture_id);
      if (it != instances_.end()) {
        instances_.erase(it);
        // Reference-counted environment lifecycle: when the last webview is
        // gone (and no creation is in flight, since its completion handler
        // still runs on the host), release the environment so the browser
        // processes can shut down and a later initializeEnvironment can
        // reconfigure it.
        if (instances_.empty() && pending_creations_ == 0) {
          webview_host_ = nullptr;
        }
        return result->Success();
      }
    }
    return result->Error(kErrorCodeInvalidId);
  } else {
    result->NotImplemented();
  }
}

void WebviewWindowsPlugin::CreateWebviewInstance(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!InitPlatform()) {
    return result->Error(kErrorUnsupportedPlatform,
                         "The platform is not supported");
  }

  if (!webview_host_) {
    // Recreate the environment from the stored options so a webview created
    // after the previous environment was released behaves identically.
    auto user_data_path = environment_options_.user_data_path
                              ? environment_options_.user_data_path
                              : platform_->GetDefaultDataDirectory();
    webview_host_ = WebviewHost::Create(
        platform_.get(), user_data_path, environment_options_.browser_exe_path,
        environment_options_.additional_arguments);
    if (!webview_host_) {
      return result->Error(kErrorCodeEnvironmentCreationFailed);
    }
  }

  auto hwnd =
      CreateWindowEx(0, window_class_.lpszClassName, L"", 0, 0, 0, 0, 0,
                     HWND_MESSAGE, nullptr, window_class_.hInstance, nullptr);

  std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>
      shared_result = std::move(result);
  ++pending_creations_;
  webview_host_->CreateWebview(
      hwnd, GetFlutterViewHwnd(), true, true,
      [shared_result, this](std::unique_ptr<Webview> webview,
                            std::unique_ptr<WebviewCreationError> error) {
        --pending_creations_;
        if (!webview) {
          // A failed creation may have been the only reason the environment
          // was alive; apply the same release-on-zero rule as dispose.
          if (instances_.empty() && pending_creations_ == 0) {
            webview_host_ = nullptr;
          }
          if (error) {
            return shared_result->Error(
                kErrorCodeWebviewCreationFailed,
                std::format(
                    "Creating the webview failed: {} (HRESULT: {:#010x})",
                    error->message, error->hr));
          }
          return shared_result->Error(kErrorCodeWebviewCreationFailed,
                                      "Creating the webview failed.");
        }

        auto bridge = std::make_unique<WebviewBridge>(
            messenger_, textures_, platform_->graphics_context(),
            std::move(webview));
        auto texture_id = bridge->texture_id();
        instances_[texture_id] = std::move(bridge);

        auto response = flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue("textureId"),
             flutter::EncodableValue(texture_id)},
        });

        shared_result->Success(response);
      });
}

bool WebviewWindowsPlugin::InitPlatform() {
  if (!platform_) {
    platform_ = std::make_unique<WebviewPlatform>();
  }
  return platform_->IsSupported();
}

HWND WebviewWindowsPlugin::GetFlutterViewHwnd() {
  if (!registrar_) {
    return nullptr;
  }
  auto view = registrar_->GetView();
  if (!view) {
    return nullptr;
  }
  return view->GetNativeWindow();
}

}  // namespace

void WebviewWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  WebviewWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
