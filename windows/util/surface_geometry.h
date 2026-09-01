#pragma once

#include <windows.h>

#include <cmath>
#include <cstddef>

namespace util {

// The geometry a webview surface is asked to take: its size in logical
// pixels, the scale factor that turns logical pixels into raw ones, and the
// position of its top-left corner, in logical pixels, relative to the client
// origin of the window given to ICoreWebView2Controller::put_ParentWindow.
struct SurfaceGeometry {
  size_t width = 0;
  size_t height = 0;
  float scale_factor = 1.0f;
  double offset_x = 0.0;
  double offset_y = 0.0;
};

// Whether |a| and |b| describe the same surface extent: the same logical size
// at the same scale. Only an extent change requires the composition surface
// to be resized and the texture's frame pool recreated. A webview that merely
// moved, which happens every frame while it scrolls or animates, keeps both
// and only needs its Bounds origin updated.
inline bool SameExtent(const SurfaceGeometry& a, const SurfaceGeometry& b) {
  return a.width == b.width && a.height == b.height &&
         a.scale_factor == b.scale_factor;
}

// Bounds for |geometry|, in raw pixels, relative to the parent window's
// client origin.
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
inline RECT SurfaceBounds(const SurfaceGeometry& geometry) {
  const auto left = static_cast<LONG>(
      std::lround(geometry.offset_x * geometry.scale_factor));
  const auto top = static_cast<LONG>(
      std::lround(geometry.offset_y * geometry.scale_factor));

  RECT bounds;
  bounds.left = left;
  bounds.top = top;
  bounds.right =
      left + static_cast<LONG>(geometry.width * geometry.scale_factor);
  bounds.bottom =
      top + static_cast<LONG>(geometry.height * geometry.scale_factor);
  return bounds;
}

}  // namespace util
