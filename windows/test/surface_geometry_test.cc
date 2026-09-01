#include "util/surface_geometry.h"

#include <gtest/gtest.h>

namespace util {
namespace {

SurfaceGeometry Geometry(size_t width, size_t height, float scale_factor,
                         double offset_x, double offset_y) {
  SurfaceGeometry geometry;
  geometry.width = width;
  geometry.height = height;
  geometry.scale_factor = scale_factor;
  geometry.offset_x = offset_x;
  geometry.offset_y = offset_y;
  return geometry;
}

TEST(SurfaceGeometryTest, PlacesSurfaceAtWindowOriginWhenNotInset) {
  const RECT bounds = SurfaceBounds(Geometry(800, 600, 1.0f, 0.0, 0.0));

  EXPECT_EQ(bounds.left, 0);
  EXPECT_EQ(bounds.top, 0);
  EXPECT_EQ(bounds.right, 800);
  EXPECT_EQ(bounds.bottom, 600);
}

TEST(SurfaceGeometryTest, OffsetBecomesTheBoundsOriginAndKeepsTheExtent) {
  // The bug this guards: a hardcoded (0,0) origin made WebView2 place popups
  // relative to the window instead of the webview, displacing them by the
  // inset.
  const RECT bounds = SurfaceBounds(Geometry(800, 600, 1.0f, 200.0, 150.0));

  EXPECT_EQ(bounds.left, 200);
  EXPECT_EQ(bounds.top, 150);
  EXPECT_EQ(bounds.right - bounds.left, 800);
  EXPECT_EQ(bounds.bottom - bounds.top, 600);
}

TEST(SurfaceGeometryTest, ScalesOriginAndExtentTogether) {
  // Bounds are raw pixels (COREWEBVIEW2_BOUNDS_MODE_USE_RAW_PIXELS), so the
  // origin has to be scaled by the same factor as the size. Scaling only one
  // of the two would misplace popups on any non-unity DPI.
  const RECT bounds = SurfaceBounds(Geometry(800, 600, 2.0f, 200.0, 150.0));

  EXPECT_EQ(bounds.left, 400);
  EXPECT_EQ(bounds.top, 300);
  EXPECT_EQ(bounds.right, 2000);
  EXPECT_EQ(bounds.bottom, 1500);
}

TEST(SurfaceGeometryTest, RoundsTheOriginAtFractionalScaleFactors) {
  // 123 * 1.25 = 153.75 and 41 * 1.25 = 51.25. Truncating would bias every
  // popup up and to the left at the common 125% and 150% display scales.
  const RECT bounds = SurfaceBounds(Geometry(100, 100, 1.25f, 123.0, 41.0));

  EXPECT_EQ(bounds.left, 154);
  EXPECT_EQ(bounds.top, 51);
  EXPECT_EQ(bounds.right, 279);
  EXPECT_EQ(bounds.bottom, 176);
}

TEST(SurfaceGeometryTest, KeepsNegativeOffsetsSigned) {
  // A webview scrolled partly above or left of the viewport has a negative
  // offset. Clamping it to zero would misplace popups by the hidden amount.
  const RECT bounds = SurfaceBounds(Geometry(300, 200, 1.0f, -50.0, -25.0));

  EXPECT_EQ(bounds.left, -50);
  EXPECT_EQ(bounds.top, -25);
  EXPECT_EQ(bounds.right, 250);
  EXPECT_EQ(bounds.bottom, 175);
}

TEST(SurfaceGeometryTest, MovingWithoutResizingKeepsTheExtent) {
  // A webview that scrolls or animates across the window reports a new
  // origin every frame. That must not count as a resize: a resize recreates
  // the composition surface and the texture's frame pool, far too much work
  // to repeat sixty times a second for a move.
  EXPECT_TRUE(SameExtent(Geometry(800, 600, 1.25f, 10.0, 20.0),
                         Geometry(800, 600, 1.25f, 300.0, 40.0)));
}

TEST(SurfaceGeometryTest, ResizingChangesTheExtent) {
  const SurfaceGeometry base = Geometry(800, 600, 1.0f, 0.0, 0.0);

  EXPECT_FALSE(SameExtent(base, Geometry(801, 600, 1.0f, 0.0, 0.0)));
  EXPECT_FALSE(SameExtent(base, Geometry(800, 599, 1.0f, 0.0, 0.0)));
}

TEST(SurfaceGeometryTest, RescalingChangesTheExtentEvenAtEqualRawSize) {
  // 100 logical pixels at 2x and 200 at 1x cover the same raw pixels, but
  // the rasterization scale differs, so the surface has to be reconfigured.
  EXPECT_FALSE(SameExtent(Geometry(100, 100, 2.0f, 0.0, 0.0),
                          Geometry(200, 200, 1.0f, 0.0, 0.0)));
}

}  // namespace
}  // namespace util
