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

        // Resolve the Dyslexia themes' body family while we're already in App.init
        // on the main thread, AppKit is up, and the bundled OpenDyslexic has just
        // been registered. Doing this here (instead of from a `static let` lazy
        // initializer that fires on first MDVTheme access) was a stability fix:
        // on macOS 14.4 the lazy-static-let path triggered a Swift runtime
        // EXC_BREAKPOINT inside ThemeManager.init when MDVTheme.standardErin
        // was constructed for the first time. Resolving up-front avoids that.
        let families = NSFontManager.shared.availableFontFamilies
        for candidate in ["Dyslexie", "Dyslexie LT", "Dyslexie Regular"] {
            if families.contains(candidate) {
                dyslexiaBodyFamily = candidate
                return
            }
        }
        // Fallback already in place from the property's default value.
    }

    /// Family name to use for the Standard Erin themes' body text. Prefers
    /// Dyslexie (Christian Boer's commercial face) when the user has it
    /// installed system-wide via Font Book; falls back to bundled OpenDyslexic.
    /// Both faces share the weighted-bottom design and have effectively the
    /// same measure and cap height, so the rest of the theme works for either.
    /// Set in `registerBundledFonts()` — App.init calls that before any
    /// MDVTheme accesses this, so by the time the theme constructs the value
    /// is final.
    static private(set) var dyslexiaBodyFamily: String = "OpenDyslexic"

    /// Whether the resolved family is the user's system-installed Dyslexie
    /// rather than the bundled OpenDyslexic. Surfaced for menu help text.
    static var dyslexiaUsingDyslexie: Bool {
        dyslexiaBodyFamily != "OpenDyslexic"
    }
}
