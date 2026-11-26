#include "webview_platform.h"

#include <DispatcherQueue.h>
#include <shlobj.h>
#include <windows.graphics.capture.h>
#include <windows.system.h>

#include <filesystem>
#include <iostream>

WebviewPlatform::WebviewPlatform()
    : rohelper_(std::make_unique<rx::RoHelper>(RO_INIT_SINGLETHREADED)) {
  if (rohelper_->WinRtAvailable()) {
    if (!EnsureDispatcherQueue()) {
      std::cerr << "Initializing the UI thread dispatcher queue failed."
                << std::endl;
      return;
    }

    if (!IsGraphicsCaptureSessionSupported()) {
      std::cerr << "Windows::Graphics::Capture::GraphicsCaptureSession is not "
                   "supported."
                << std::endl;
      return;
    }

    graphics_context_ = std::make_unique<GraphicsContext>(rohelper_.get());
    valid_ = graphics_context_->IsValid();
  }
}

bool WebviewPlatform::EnsureDispatcherQueue() {
  HSTRING class_name;
  HSTRING_HEADER header;
  winrt::com_ptr<ABI::Windows::System::IDispatcherQueueStatics> statics;
  winrt::com_ptr<ABI::Windows::System::IDispatcherQueue> queue;
  if (FAILED(rohelper_->GetStringReference(
          RuntimeClass_Windows_System_DispatcherQueue, &class_name, &header)) ||
      FAILED(rohelper_->GetActivationFactory(
          class_name, __uuidof(ABI::Windows::System::IDispatcherQueueStatics),
          statics.put_void())) ||
      FAILED(statics->GetForCurrentThread(queue.put()))) {
    return false;
  }
  // A thread has one dispatcher queue. If the host created it, the host
  // retains its controller and controls when the queue shuts down.
  if (queue) {
    return true;
  }

  DispatcherQueueOptions options{sizeof(DispatcherQueueOptions),
                                 DQTYPE_THREAD_CURRENT, DQTAT_COM_STA};
  return SUCCEEDED(rohelper_->CreateDispatcherQueueController(
      options, dispatcher_queue_controller_.put()));
}

bool WebviewPlatform::IsGraphicsCaptureSessionSupported() {
  HSTRING className;
  HSTRING_HEADER classNameHeader;

  if (FAILED(rohelper_->GetStringReference(
          RuntimeClass_Windows_Graphics_Capture_GraphicsCaptureSession,
          &className, &classNameHeader))) {
    return false;
  }

  winrt::com_ptr<
      ABI::Windows::Graphics::Capture::IGraphicsCaptureSessionStatics>
      capture_session_statics;
  if (FAILED(rohelper_->GetActivationFactory(
          className,
          __uuidof(
              ABI::Windows::Graphics::Capture::IGraphicsCaptureSessionStatics),
          capture_session_statics.put_void()))) {
    return false;
  }

  boolean is_supported = false;
  if (FAILED(capture_session_statics->IsSupported(&is_supported))) {
    return false;
  }

  return !!is_supported;
}

std::optional<std::wstring> WebviewPlatform::GetDefaultDataDirectory() {
  PWSTR path_tmp;
  if (!SUCCEEDED(
          SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path_tmp))) {
    return std::nullopt;
  }
  auto path = std::filesystem::path(path_tmp);
  CoTaskMemFree(path_tmp);

  wchar_t filename[MAX_PATH];
  GetModuleFileName(nullptr, filename, MAX_PATH);
  path /= "flutter_webview_windows";
  path /= std::filesystem::path(filename).stem();

  return path.wstring();
}
