//
//  MathFontBundle.swift
//  mdv-local addition — not part of upstream SwiftMath.
//
//  Upstream locates `mathFonts.bundle` through SwiftPM's generated
//  `Bundle.module`, which looks for `SwiftMath_SwiftMath.bundle` at the
//  *root* of the app bundle. codesign rejects anything at the bundle root
//  ("unsealed contents present in the bundle root"), so mdv ships the fonts
//  in Contents/Resources instead and resolves them here.
//

import Foundation

enum MathFontBundle {
    /// `mathFonts.bundle`: from the app's Resources when running as a bundled
    /// app, otherwise the vendored copy next to these sources (for `swift run`
    /// and tests).
    static let url: URL? = {
        if let bundled = Bundle.main.url(forResource: "mathFonts", withExtension: "bundle") {
            return bundled
        }
        // …/Vendor/SwiftMath/Sources/SwiftMath/MathFontBundle.swift → …/Vendor/SwiftMath/mathFonts.bundle
        let vendored = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SwiftMath
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // Vendor/SwiftMath
            .appendingPathComponent("mathFonts.bundle")
        return FileManager.default.fileExists(atPath: vendored.path) ? vendored : nil
    }()
}
