import MarkdownUI
import SwiftUI
import XCTest
@testable import mdv

final class RemoteGatedInlineImageProviderTests: XCTestCase {
    private final class RecordingProvider: InlineImageProvider, @unchecked Sendable {
        private(set) var requested: [URL] = []

        func image(with url: URL, label: String) async throws -> Image {
            requested.append(url)
            return Image(systemName: "checkmark")
        }
    }

    func testBlocksRemoteURLsWithoutCallingUpstreamWhenToggleIsOff() async throws {
        let upstream = RecordingProvider()
        let provider = RemoteGatedInlineImageProvider(loadRemoteImages: false, upstream: upstream)

        for raw in ["https://example.com/pixel.png", "http://example.com/a.gif", "HTTPS://EXAMPLE.COM/b.png", "ftp://example.com/c.png"] {
            _ = try await provider.image(with: URL(string: raw)!, label: "tracker")
        }

        XCTAssertEqual(upstream.requested, [])
    }

    func testPassesLocalURLsThroughWhenToggleIsOff() async throws {
        let upstream = RecordingProvider()
        let provider = RemoteGatedInlineImageProvider(loadRemoteImages: false, upstream: upstream)
        let local = [
            URL(fileURLWithPath: "/tmp/icon.png"),
            URL(string: "data:image/png;base64,iVBORw0KGgo=")!,
            URL(string: "images/icon.png")!,
        ]

        for url in local {
            _ = try await provider.image(with: url, label: "local")
        }

        XCTAssertEqual(upstream.requested, local)
    }

    func testPassesRemoteURLsThroughWhenToggleIsOn() async throws {
        let upstream = RecordingProvider()
        let provider = RemoteGatedInlineImageProvider(loadRemoteImages: true, upstream: upstream)
        let remote = URL(string: "https://example.com/pixel.png")!

        _ = try await provider.image(with: remote, label: "remote")

        XCTAssertEqual(upstream.requested, [remote])
    }

    func testRelativeURLResolvedAgainstRemoteBaseCountsAsRemote() {
        let base = URL(string: "https://example.com/docs/")!
        XCTAssertTrue(RemoteGatedInlineImageProvider.isRemote(URL(string: "pixel.png", relativeTo: base)!))
        XCTAssertFalse(RemoteGatedInlineImageProvider.isRemote(URL(string: "pixel.png")!))
    }
}
