import Foundation
import CoreText

/// Bundled fonts registered into the process-local font space at app launch.
/// We don't install fonts on the user's system — these live in
/// `mdv.app/Contents/Resources/` and disappear when the app exits.
enum FontRegistration {
    /// PostScript file names (without extension) of the bundled Alegreya weights.
    /// Six weights cover the full markdown spectrum (regular/italic body, semibold
    /// emphasis, bold for strong/headings, extrabold for h1/h2). Black and the
    /// rarer italic variants are skipped to keep the bundle around 1.7 MB.
    private static let bundledFonts = [
        "Alegreya-Regular",
        "Alegreya-Italic",
        "Alegreya-Medium",
        "Alegreya-Bold",
        "Alegreya-BoldItalic",
        "Alegreya-ExtraBold",
    ]

    static func registerBundledFonts() {
        for name in bundledFonts {
            guard let url = Bundle.main.url(forResource: name, withExtension: "otf") else {
                NSLog("[mdv] missing bundled font: \(name).otf")
                continue
            }
            var error: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if !ok, let e = error?.takeRetainedValue() {
                // Already-registered errors are benign on relaunch in the same
                // session; log and move on.
                NSLog("[mdv] register \(name): \(e)")
            }
        }
    }
}
