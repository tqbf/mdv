// mdv patch (see Vendor/MarkdownUI/README.md) — not part of upstream 2.4.1.
//
// Upstream resolves inline images exclusively in `InlineText`'s `.task`, so a
// renderer that runs no async work (SwiftUI's `ImageRenderer`, used by mdv's
// print pipeline) draws inline images as nothing at all. This environment
// value lets a caller hand over images it has *already* resolved, keyed by the
// image source as written in the markdown; they are merged into the loaded
// ones at render time. Cleared by default, so on-screen behaviour is
// unchanged (the `.task` still loads images and still wins for equal keys).

import SwiftUI

extension View {
  /// Supplies inline images that are already resolved, keyed by the image
  /// source exactly as it appears in the markdown (e.g. `![…](source)`'s
  /// `source`).
  ///
  /// Use this when the images must be drawn without waiting for an
  /// asynchronous load — most notably under `ImageRenderer`, which never runs
  /// `View.task`, where an unresolved inline image renders as nothing.
  ///
  /// - Parameter images: Images to draw instead of loading, keyed by source.
  /// - Returns: A view that draws those images for itself and its child views.
  public func markdownResolvedInlineImages(_ images: [String: Image]) -> some View {
    self.environment(\.resolvedInlineImages, images)
  }
}

extension EnvironmentValues {
  /// Inline images already resolved by the caller, keyed by image source.
  public var resolvedInlineImages: [String: Image] {
    get { self[ResolvedInlineImagesKey.self] }
    set { self[ResolvedInlineImagesKey.self] = newValue }
  }
}

private struct ResolvedInlineImagesKey: EnvironmentKey {
  static let defaultValue: [String: Image] = [:]
}
