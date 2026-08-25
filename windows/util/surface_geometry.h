#pragma once

#include <windows.h>

#include <cmath>
#include <cstddef>

namespace util {

// Bounds for a webview of |width| x |height| logical pixels whose top-left
// corner sits |offset_x|, |offset_y| logical pixels from the client origin of
// the window given to ICoreWebView2Controller::put_ParentWindow.
//
// The origin matters even in composition hosting, where the visual drives
// rendering. Bounds is documented as relative to ParentWindow, and it is what
// WebView2 uses for everything it has to place in host-window coordinates:
// select dropdowns, autofill and passkey bubbles, context menus, permission
// and print dialogs, accessibility hit-testing. A (0,0) origin reported for an
// inset webview displaces all of them by exactly the inset.
//
// Returned in raw pixels, matching COREWEBVIEW2_BOUNDS_MODE_USE_RAW_PIXELS.
// The origin is rounded rather than truncated so a fractional scale factor
// cannot bias every popup a pixel up and to the left. The extent keeps the
// truncating cast the surface size itself uses, so a webview at the window
// origin gets byte-identical bounds to before.
inline RECT SurfaceBounds(size_t width, size_t height, float scale_factor,
                          double offset_x, double offset_y) {
  const auto left = static_cast<LONG>(std::lround(offset_x * scale_factor));
  const auto top = static_cast<LONG>(std::lround(offset_y * scale_factor));

  RECT bounds;
  bounds.left = left;
  bounds.top = top;
  bounds.right = left + static_cast<LONG>(width * scale_factor);
  bounds.bottom = top + static_cast<LONG>(height * scale_factor);
  return bounds;
}

}  // namespace util
