# Standalone native unit test project.
#
# This is intentionally NOT part of the plugin build (windows/CMakeLists.txt):
# consumers of the plugin must never compile or run these tests. CI (and
# developers on Windows) build it directly:
#
#   cmake -S windows/test -B build/native_tests
#   cmake --build build/native_tests --config Release
#   ctest --test-dir build/native_tests -C Release --output-on-failure
cmake_minimum_required(VERSION 3.20)

project(webview_windows_native_tests LANGUAGES CXX)

set(WIL_VERSION "1.0.260126.7")
set(WEBVIEW_VERSION "1.0.3967.48")

include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/nuget.cmake)

# Header-only usage: the tests need the WebView2/WIL headers (for webview.h),
# not the loader import library or MSBuild .targets wiring.
ensure_nuget_package(Microsoft.Windows.ImplementationLibrary ${WIL_VERSION}
                     build/native/Microsoft.Windows.ImplementationLibrary.targets)
ensure_nuget_package(Microsoft.Web.WebView2 ${WEBVIEW_VERSION}
                     build/native/Microsoft.Web.WebView2.targets)

include(FetchContent)
FetchContent_Declare(
  googletest
  URL https://github.com/google/googletest/archive/refs/tags/v1.17.0.tar.gz
  URL_HASH SHA256=65fab701d9829d38cb77c14acdc431d2108bfdbf8979e40eb8ae567edf10b27c
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
# Match the dynamically linked runtime (/MD) used by the code under test.
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

add_executable(webview_windows_unittests
  string_converter_test.cc
  cursor_util_test.cc
  virtual_key_state_test.cc
  surface_geometry_test.cc
  ../util/string_converter.cc
  ../util/cursor_util.cc
)

target_compile_features(webview_windows_unittests PRIVATE cxx_std_23)
# Mirror the defines the plugin itself builds with (Flutter's
# apply_standard_settings). Deliberately no WIN32_LEAN_AND_MEAN: the
# MIDL-generated WebView2.h needs the COM base headers from <windows.h>.
target_compile_definitions(webview_windows_unittests PRIVATE
  UNICODE _UNICODE NOMINMAX
)

target_include_directories(webview_windows_unittests PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/..
  ${CMAKE_BINARY_DIR}/packages/Microsoft.Web.WebView2/build/native/include
  ${CMAKE_BINARY_DIR}/packages/Microsoft.Windows.ImplementationLibrary/include
)

target_link_libraries(webview_windows_unittests PRIVATE GTest::gtest_main)

include(GoogleTest)
enable_testing()
gtest_discover_tests(webview_windows_unittests DISCOVERY_TIMEOUT 60)
