#include "util/surface_geometry.h"

#include <gtest/gtest.h>

namespace util {
namespace {

TEST(SurfaceGeometryTest, PlacesSurfaceAtWindowOriginWhenNotInset) {
  const RECT bounds = SurfaceBounds(800, 600, 1.0f, 0.0, 0.0);

  EXPECT_EQ(bounds.left, 0);
  EXPECT_EQ(bounds.top, 0);
  EXPECT_EQ(bounds.right, 800);
  EXPECT_EQ(bounds.bottom, 600);
}

TEST(SurfaceGeometryTest, OffsetBecomesTheBoundsOriginAndKeepsTheExtent) {
  // The bug this guards: a hardcoded (0,0) origin made WebView2 place popups
  // relative to the window instead of the webview, displacing them by the
  // inset.
  const RECT bounds = SurfaceBounds(800, 600, 1.0f, 200.0, 150.0);

  EXPECT_EQ(bounds.left, 200);
  EXPECT_EQ(bounds.top, 150);
  EXPECT_EQ(bounds.right - bounds.left, 800);
  EXPECT_EQ(bounds.bottom - bounds.top, 600);
}

TEST(SurfaceGeometryTest, ScalesOriginAndExtentTogether) {
  // Bounds are raw pixels (COREWEBVIEW2_BOUNDS_MODE_USE_RAW_PIXELS), so the
  // origin has to be scaled by the same factor as the size. Scaling only one
  // of the two would misplace popups on any non-unity DPI.
  const RECT bounds = SurfaceBounds(800, 600, 2.0f, 200.0, 150.0);

  EXPECT_EQ(bounds.left, 400);
  EXPECT_EQ(bounds.top, 300);
  EXPECT_EQ(bounds.right, 2000);
  EXPECT_EQ(bounds.bottom, 1500);
}

TEST(SurfaceGeometryTest, RoundsTheOriginAtFractionalScaleFactors) {
  // 123 * 1.25 = 153.75 and 41 * 1.25 = 51.25. Truncating would bias every
  // popup up and to the left at the common 125% and 150% display scales.
  const RECT bounds = SurfaceBounds(100, 100, 1.25f, 123.0, 41.0);

  EXPECT_EQ(bounds.left, 154);
  EXPECT_EQ(bounds.top, 51);
  EXPECT_EQ(bounds.right, 279);
  EXPECT_EQ(bounds.bottom, 176);
}

TEST(SurfaceGeometryTest, KeepsNegativeOffsetsSigned) {
  // A webview scrolled partly above or left of the viewport has a negative
  // offset. Clamping it to zero would misplace popups by the hidden amount.
  const RECT bounds = SurfaceBounds(300, 200, 1.0f, -50.0, -25.0);

  EXPECT_EQ(bounds.left, -50);
  EXPECT_EQ(bounds.top, -25);
  EXPECT_EQ(bounds.right, 250);
  EXPECT_EQ(bounds.bottom, 175);
}

}  // namespace
}  // namespace util
