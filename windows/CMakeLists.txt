cmake_minimum_required(VERSION 3.20)

# Set CMP0175 to NEW to properly handle add_custom_command arguments
if(POLICY CMP0175)
  cmake_policy(SET CMP0175 NEW)
endif()

set(PROJECT_NAME "webview_flutter_windows")

set(WIL_VERSION "1.0.260126.7")
set(WEBVIEW_VERSION "1.0.3967.48")

message(VERBOSE "CMake system version is ${CMAKE_SYSTEM_VERSION} (using SDK ${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION})")

project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "webview_flutter_windows_plugin")

# NuGet tooling shared with the native test build (windows/test).
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/nuget.cmake)

ensure_nuget_package(Microsoft.Windows.ImplementationLibrary ${WIL_VERSION}
                     build/native/Microsoft.Windows.ImplementationLibrary.targets)
ensure_nuget_package(Microsoft.Web.WebView2 ${WEBVIEW_VERSION}
                     build/native/Microsoft.Web.WebView2.targets)

# Define source files
set(PLUGIN_SOURCES
  "webview_windows_plugin.cc"
  "webview_platform.cc"
  "webview.cc"
  "webview_host.cc"
  "webview_bridge.cc"
  "texture_bridge.cc"
  "texture_bridge_gpu.cc"
  "graphics_context.cc"
  "util/cursor_util.cc"
  "util/direct3d11.interop.cc"
  "util/rohelper.cc"
  "util/string_converter.cc"
)

# Create the plugin library
add_library(${PLUGIN_NAME} SHARED ${PLUGIN_SOURCES})

# Apply standard settings
apply_standard_settings(${PLUGIN_NAME})

# Build the plugin itself as C++23. Deliberately PRIVATE: the exported plugin
# header is plain C ABI, so the consuming app's language level must not be
# forced up by this target.
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_23)

# Configure visibility
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)

# Add dependencies
target_link_libraries(${PLUGIN_NAME} PRIVATE
  ${CMAKE_BINARY_DIR}/packages/Microsoft.Web.WebView2/build/native/Microsoft.Web.WebView2.targets
  ${CMAKE_BINARY_DIR}/packages/Microsoft.Windows.ImplementationLibrary/build/native/Microsoft.Windows.ImplementationLibrary.targets
  flutter
  flutter_wrapper_plugin
)

# Configure definitions and includes
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

# Set bundled libraries
set(webview_flutter_windows_bundled_libraries
  PARENT_SCOPE
)
