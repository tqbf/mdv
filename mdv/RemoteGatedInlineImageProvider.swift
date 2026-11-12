import MarkdownUI
import SwiftUI

/// Inline image provider (images MarkdownUI lays out as part of a run of
/// text in paragraphs, headings, and table cells, rather than as a
/// standalone image block) that honors View → Load Remote Images. MarkdownUI routes those images through a separate provider from
/// `LocalImageProvider`, and its default fetches over the network
/// unconditionally, so without this a document could still trigger remote
/// requests with the toggle off.
///
/// Blocked URLs resolve to a placeholder glyph rather than throwing:
/// MarkdownUI loads a paragraph's inline images as one group and discards
/// the whole group if any load throws. The glyph still disappears when the
/// paragraph also holds a local inline image, because MarkdownUI's default
/// loader fails on `file:`, `data:`, and relative URLs.
struct RemoteGatedInlineImageProvider: InlineImageProvider {
    let loadRemoteImages: Bool
    var upstream: any InlineImageProvider = DefaultInlineImageProvider.default

    func image(with url: URL, label: String) async throws -> Image {
        if !loadRemoteImages && Self.isRemote(url) {
            return Image(systemName: "photo")
        }
        return try await upstream.image(with: url, label: label)
    }

    /// Matches `LocalImageProvider`'s split: `file:` and `data:` URLs and
    /// scheme-less relative paths pass through because they can't reach the
    /// network; every other scheme could.
    static func isRemote(_ url: URL) -> Bool {
        guard let scheme = url.absoluteURL.scheme?.lowercased() else { return false }
        return scheme != "file" && scheme != "data"
    }
}
