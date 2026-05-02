import Foundation
import AppKit
import CoreText

/// Bundled fonts registered into the process-local font space at app launch.
/// We don't install fonts on the user's system — these live in
/// `mdv.app/Contents/Resources/` and disappear when the app exits.
enum FontRegistration {
    /// PostScript file names (without extension) of the bundled font weights.
    /// Alegreya: six weights for the Sevilla reading theme.
    /// OpenDyslexic: four weights for the Dyslexia themes — the FOSS face
    /// purpose-built for dyslexic readability (weighted glyph bottoms).
    private static let bundledFonts = [
        "Alegreya-Regular",
        "Alegreya-Italic",
        "Alegreya-Medium",
        "Alegreya-Bold",
        "Alegreya-BoldItalic",
        "Alegreya-ExtraBold",
        "OpenDyslexic-Regular",
        "OpenDyslexic-Italic",
        "OpenDyslexic-Bold",
        "OpenDyslexic-Bold-Italic",
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

    /// Family name to use for the Dyslexia themes' body text. Prefers Dyslexie
    /// (Christian Boer's commercial face — weighted bottoms, broad European
    /// adoption in education) when the user has it installed system-wide via
    /// Font Book; falls back to the bundled OpenDyslexic which has effectively
    /// the same measure and cap height. Resolved on first access — App.init
    /// has already registered OpenDyslexic by the time any theme accesses
    /// this, so the fallback is always available.
    static let dyslexiaBodyFamily: String = {
        let families = NSFontManager.shared.availableFontFamilies
        // Common family-name strings the Dyslexie installer uses on macOS.
        // Prefer the canonical family in priority order; users with the
        // "Dyslexie LT" variant will hit the second match.
        for candidate in ["Dyslexie", "Dyslexie LT", "Dyslexie Regular"] {
            if families.contains(candidate) { return candidate }
        }
        return "OpenDyslexic"
    }()

    /// Whether the resolved Dyslexia family is the user's system-installed
    /// Dyslexie rather than the bundled OpenDyslexic. Surfaced for the
    /// theme-menu help-text so the user can tell which face is in play.
    static var dyslexiaUsingDyslexie: Bool {
        dyslexiaBodyFamily != "OpenDyslexic"
    }
}
