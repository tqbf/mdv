import SwiftUI
import MarkdownUI

/// A document theme. Affects only the markdown viewer pane and the sidebar tint —
/// the rest of the window chrome stays system-light/dark so the app still feels
/// native. Each theme owns the full palette, no light/dark inheritance: the user
/// picked it, that's the look.
struct MDVTheme: Identifiable, Hashable {
    let id: String
    let name: String
    /// Hint for SwiftUI defaults (find bar, toolbar text inside the viewer overlay,
    /// etc.) so primary/secondary system colors land on the right side of the contrast
    /// curve for this theme's background.
    let isDark: Bool

    let background: Color
    let secondaryBackground: Color   // code blocks, table-stripes
    let text: Color
    let secondaryText: Color
    let tertiaryText: Color
    let heading: Color
    let link: Color
    let strong: Color                // bold
    let border: Color
    let divider: Color
    let blockquoteBar: Color

    /// Subtle hue laid over the sidebar's vibrancy so the sidebar reflects the
    /// current theme without drowning out the system look. Kept at low opacity.
    let sidebarTint: Color
    let sidebarTintOpacity: Double

    // MARK: Typography

    /// Font family for body text, headings, blockquote, etc. Code blocks
    /// always use the system monospace regardless of this setting.
    var bodyFontFamily: FontProperties.Family = .system()
    /// Default `Theme.gitHub` uses 16pt body. Reading-tuned themes can bump
    /// this up — Alegreya's x-height is generous so 17pt feels equivalent
    /// to system 16pt while easing eye fatigue on long texts.
    var baseFontSize: CGFloat = 16
    /// Extra leading between lines, in em-relative units. MarkdownUI's gitHub
    /// theme uses 0.25em — that's tight for serif body. Long-form serif reading
    /// wants 0.4–0.5em on top of the natural ~1.2 line height.
    var paragraphLineSpacingEm: CGFloat = 0.25
    /// Horizontal padding around the rendered article. Theme-controlled so a
    /// reading theme can set a measure (line length) closer to the optimum
    /// 60–75 characters.
    var articleHorizontalPadding: CGFloat = 34
    /// Optional max width for the article column. When set, the LazyVStack is
    /// constrained to this width and centered, giving a robust measure that
    /// doesn't widen with the window. Reading themes use this; default is
    /// nil so non-reading themes keep filling the available width.
    var articleMaxWidth: CGFloat? = nil

    // MARK: Heading scale

    /// Heading sizes in em units (relative to body). Defaults match
    /// `Theme.gitHub`'s scale (2 / 1.5 / 1.25). Reading themes can tone these
    /// down — heavy serif headings at the GitHub scale dominate the page and
    /// pull it toward "designed document" rather than "reader".
    var h1SizeEm: CGFloat = 2.0
    var h2SizeEm: CGFloat = 1.5
    var h3SizeEm: CGFloat = 1.25

    /// Whether to render a divider rule beneath H1/H2 (the GitHub-style
    /// horizontal line). Quieter reading themes turn the H2 rule off.
    var showH1Rule: Bool = true
    var showH2Rule: Bool = true
}

extension MDVTheme {
    /// Mirror of `Theme.gitHub`'s shape but with explicit per-theme colors. Same
    /// block builders so spacing/typography stays consistent across themes.
    var markdownTheme: Theme {
        let bg = self.background
        let sbg = self.secondaryBackground
        let txt = self.text
        let stxt = self.secondaryText
        let ttxt = self.tertiaryText
        let lnk = self.link
        let bdr = self.border
        let div = self.divider
        let bqBar = self.blockquoteBar
        let head = self.heading
        let strong = self.strong

        let family = self.bodyFontFamily
        let bodySize = self.baseFontSize
        let lineEm = self.paragraphLineSpacingEm
        let h1 = self.h1SizeEm
        let h2 = self.h2SizeEm
        let h3 = self.h3SizeEm
        let h1Rule = self.showH1Rule
        let h2Rule = self.showH2Rule

        return Theme()
            .text {
                FontFamily(family)
                ForegroundColor(txt)
                BackgroundColor(bg)
                FontSize(bodySize)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.85))
                BackgroundColor(sbg)
            }
            .strong {
                FontWeight(.semibold)
                ForegroundColor(strong)
            }
            .link {
                ForegroundColor(lnk)
            }
            .heading1 { configuration in
                VStack(alignment: .leading, spacing: 0) {
                    configuration.label
                        .relativePadding(.bottom, length: .em(0.3))
                        .relativeLineSpacing(.em(0.125))
                        .markdownMargin(top: 24, bottom: 16)
                        .markdownTextStyle {
                            FontWeight(.semibold)
                            FontSize(.em(h1))
                            ForegroundColor(head)
                        }
                    if h1Rule { Divider().overlay(div) }
                }
            }
            .heading2 { configuration in
                VStack(alignment: .leading, spacing: 0) {
                    configuration.label
                        .relativePadding(.bottom, length: .em(0.3))
                        .relativeLineSpacing(.em(0.125))
                        .markdownMargin(top: 24, bottom: 16)
                        .markdownTextStyle {
                            FontWeight(.semibold)
                            FontSize(.em(h2))
                            ForegroundColor(head)
                        }
                    if h2Rule { Divider().overlay(div) }
                }
            }
            .heading3 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(h3))
                        ForegroundColor(head)
                    }
            }
            .heading4 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        ForegroundColor(head)
                    }
            }
            .heading5 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(0.875))
                        ForegroundColor(head)
                    }
            }
            .heading6 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(0.85))
                        ForegroundColor(ttxt)
                    }
            }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(lineEm))
                    .markdownMargin(top: 0, bottom: 16)
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(bqBar)
                        .relativeFrame(width: .em(0.2))
                    configuration.label
                        .markdownTextStyle { ForegroundColor(stxt) }
                        .relativePadding(.horizontal, length: .em(1))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .codeBlock { configuration in
                ScrollView(.horizontal) {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .relativeLineSpacing(.em(0.225))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.85))
                        }
                        .padding(16)
                }
                .background(sbg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .markdownMargin(top: 0, bottom: 16)
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.25))
            }
            .table { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTableBorderStyle(.init(color: bdr))
                    .markdownTableBackgroundStyle(.alternatingRows(bg, sbg))
                    .markdownMargin(top: 0, bottom: 16)
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        if configuration.row == 0 {
                            FontWeight(.semibold)
                        }
                        BackgroundColor(nil)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 13)
                    .relativeLineSpacing(.em(0.25))
            }
            .thematicBreak {
                Divider()
                    .relativeFrame(height: .em(0.25))
                    .overlay(bdr)
                    .markdownMargin(top: 24, bottom: 24)
            }
    }
}

// MARK: - Catalog

extension MDVTheme {
    /// Approximation of GitHub's light/dark palette, hard-set to its light side.
    /// Acts as the sane default and the "I just want to read" choice.
    static let highContrast = MDVTheme(
        id: "high-contrast",
        name: "High Contrast",
        isDark: false,
        background: Color(rgba: 0xFFFFFFFF),
        secondaryBackground: Color(rgba: 0xF3F4F6FF),
        text: Color(rgba: 0x0A0A0AFF),
        secondaryText: Color(rgba: 0x4B5563FF),
        tertiaryText: Color(rgba: 0x6B7280FF),
        heading: Color(rgba: 0x000000FF),
        link: Color(rgba: 0x1D6FE0FF),
        strong: Color(rgba: 0x000000FF),
        border: Color(rgba: 0xE5E7EBFF),
        divider: Color(rgba: 0xD1D5DBFF),
        blockquoteBar: Color(rgba: 0xD1D5DBFF),
        sidebarTint: Color(rgba: 0xFFFFFFFF),
        sidebarTintOpacity: 0.0
    )

    static let charcoal = MDVTheme(
        id: "charcoal",
        name: "Charcoal",
        isDark: true,
        background: Color(rgba: 0x2B2E33FF),
        secondaryBackground: Color(rgba: 0x35393FFF),
        text: Color(rgba: 0xE6E7EAFF),
        secondaryText: Color(rgba: 0xB0B3BAFF),
        tertiaryText: Color(rgba: 0x8A8E96FF),
        heading: Color(rgba: 0xFFFFFFFF),
        link: Color(rgba: 0x6FB1FFFF),
        strong: Color(rgba: 0xFFFFFFFF),
        border: Color(rgba: 0x4A4E55FF),
        divider: Color(rgba: 0x444850FF),
        blockquoteBar: Color(rgba: 0x4A4E55FF),
        sidebarTint: Color(rgba: 0x2B2E33FF),
        sidebarTintOpacity: 0.18
    )

    /// Ethan Schoonover's Solarized Light palette.
    /// base03→base3 background ramp, yellow heading, blue link, orange accent.
    static let solarizedLight = MDVTheme(
        id: "solarized-light",
        name: "Solarized Light",
        isDark: false,
        background: Color(rgba: 0xFDF6E3FF),  // base3
        secondaryBackground: Color(rgba: 0xEEE8D5FF), // base2
        text: Color(rgba: 0x586E75FF),        // base01
        secondaryText: Color(rgba: 0x657B83FF), // base00
        tertiaryText: Color(rgba: 0x93A1A1FF), // base1
        heading: Color(rgba: 0x073642FF),     // base02 — strong
        link: Color(rgba: 0x268BD2FF),        // blue
        strong: Color(rgba: 0x073642FF),
        border: Color(rgba: 0xDED7C2FF),
        divider: Color(rgba: 0xDED7C2FF),
        blockquoteBar: Color(rgba: 0xCB4B16FF), // orange — accents the bar
        sidebarTint: Color(rgba: 0xFDF6E3FF),
        sidebarTintOpacity: 0.55
    )

    /// Long-form reading theme using bundled Alegreya (a Spanish-tradition
    /// serif designed by Juan Pablo del Peral, optimized for sustained text).
    /// Warm parchment background — pure white tires the eyes — with soft
    /// warm-brown text and azulejo-blue links. Tuned for sustained reading:
    /// 17pt body, 1.55× leading, ~620pt fixed-width column (≈70ch at this
    /// size), reduced heading scale, only H1 carries a (faded) rule.
    /// See TYPOGRAPHY.md for the rationale behind each number.
    static let sevilla = MDVTheme(
        id: "sevilla",
        name: "Sevilla",
        isDark: false,
        background: Color(rgba: 0xF4EFE3FF),          // desaturated warm cream — less yellow than parchment
        secondaryBackground: Color(rgba: 0xEAE5D6FF), // for code blocks / table stripes
        text: Color(rgba: 0x42372CFF),                // subtly lighter than the heading — counteracts Alegreya's natural heft and keeps body distinct from H*
        secondaryText: Color(rgba: 0x6A5C4DFF),
        tertiaryText: Color(rgba: 0x968874FF),
        heading: Color(rgba: 0x2D2118FF),             // darker cordovan — weight + size + this delta carry the hierarchy
        link: Color(rgba: 0x2C5F8DFF),                // muted azulejo blue
        strong: Color(rgba: 0x42372CFF),              // = body color; semibold weight alone provides emphasis (don't borrow heading darkness)
        border: Color(rgba: 0xE6DEC2FF),
        divider: Color(rgba: 0xE6DEC2FF),             // quieter rule for H1
        blockquoteBar: Color(rgba: 0xB0623EFF),       // terracotta
        sidebarTint: Color(rgba: 0xF4EFE3FF),
        sidebarTintOpacity: 0.55,
        bodyFontFamily: .custom("Alegreya"),
        baseFontSize: 17,
        paragraphLineSpacingEm: 0.55,                 // total ≈ 1.6× — Alegreya needs air
        articleHorizontalPadding: 30,                 // small breathing room when window is narrow
        articleMaxWidth: 620,                         // ≈75–78ch at 17pt Alegreya — upper end of the comfort zone
        h1SizeEm: 1.7,                                // down from 2.0 — let spacing carry hierarchy
        h2SizeEm: 1.25,                               // down from 1.5
        h3SizeEm: 1.1,                                // down from 1.25
        showH1Rule: true,                             // single faded rule under H1 for orientation
        showH2Rule: false                             // remove H2 rule — too heavy in long-form
    )

    static let solarizedDark = MDVTheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        isDark: true,
        background: Color(rgba: 0x002B36FF),  // base03
        secondaryBackground: Color(rgba: 0x073642FF), // base02
        text: Color(rgba: 0x93A1A1FF),        // base1
        secondaryText: Color(rgba: 0x839496FF), // base0
        tertiaryText: Color(rgba: 0x657B83FF), // base00
        heading: Color(rgba: 0xEEE8D5FF),     // base2
        link: Color(rgba: 0x268BD2FF),
        strong: Color(rgba: 0xFDF6E3FF),
        border: Color(rgba: 0x0E4753FF),
        divider: Color(rgba: 0x0E4753FF),
        blockquoteBar: Color(rgba: 0xB58900FF), // yellow accent
        sidebarTint: Color(rgba: 0x002B36FF),
        sidebarTintOpacity: 0.32
    )

    /// Amber-on-black CRT vibe: pure black background, hi-vis amber for headings,
    /// yellow link.
    static let phosphor = MDVTheme(
        id: "phosphor",
        name: "Phosphor",
        isDark: true,
        background: Color(rgba: 0x000000FF),
        secondaryBackground: Color(rgba: 0x141414FF),
        text: Color(rgba: 0xF5F5F5FF),
        secondaryText: Color(rgba: 0xB8B8B8FF),
        tertiaryText: Color(rgba: 0x7A7A7AFF),
        heading: Color(rgba: 0xFFA500FF), // bright amber
        link: Color(rgba: 0xFFD43BFF),    // yellow
        strong: Color(rgba: 0xFFFFFFFF),
        border: Color(rgba: 0x2A2A2AFF),
        divider: Color(rgba: 0x2A2A2AFF),
        blockquoteBar: Color(rgba: 0xFFA500FF),
        sidebarTint: Color(rgba: 0x000000FF),
        sidebarTintOpacity: 0.30
    )

    /// Deep navy, mint heading, cream link — a calm low-light palette.
    static let twilight = MDVTheme(
        id: "twilight",
        name: "Twilight",
        isDark: true,
        background: Color(rgba: 0x0A0F14FF),
        secondaryBackground: Color(rgba: 0x121820FF),
        text: Color(rgba: 0xB0B5BCFF),
        secondaryText: Color(rgba: 0x8C9298FF),
        tertiaryText: Color(rgba: 0x5B6168FF),
        heading: Color(rgba: 0x6EBA7FFF), // mint green
        link: Color(rgba: 0xFFD580FF),    // cream/yellow
        strong: Color(rgba: 0xD8DEE9FF),
        border: Color(rgba: 0x1E252DFF),
        divider: Color(rgba: 0x1E252DFF),
        blockquoteBar: Color(rgba: 0x6EBA7FFF),
        sidebarTint: Color(rgba: 0x0A0F14FF),
        sidebarTintOpacity: 0.32
    )

    static let all: [MDVTheme] = [
        .highContrast,
        .sevilla,
        .charcoal,
        .solarizedLight,
        .solarizedDark,
        .phosphor,
        .twilight,
    ]

    static let `default`: MDVTheme = .highContrast

    static func byID(_ id: String) -> MDVTheme {
        all.first(where: { $0.id == id }) ?? .default
    }
}

// MARK: - ThemeManager

/// Owns the user's current theme choice. Backed by `@AppStorage` so the
/// last-selected theme persists across launches without any explicit save.
final class ThemeManager: ObservableObject {
    @AppStorage("mdv_theme_id") private var storedID: String = MDVTheme.default.id

    @Published var current: MDVTheme = .default

    init() {
        // Pull initial value from @AppStorage. The property wrapper isn't
        // observable for our @Published mirror, so we sync once at init and
        // again on every set(_:).
        self.current = MDVTheme.byID(storedID)
    }

    func set(_ theme: MDVTheme) {
        current = theme
        storedID = theme.id
    }
}
