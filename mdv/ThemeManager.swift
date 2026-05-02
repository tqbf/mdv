import AppKit
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
    /// Default body size. SF Pro at 16pt is the macOS body baseline; reading
    /// themes that bundle a custom face often bump this (Sevilla → 17 to match
    /// Alegreya's x-height; Charcoal → 16.5 for half-pt SF Pro crispness).
    var baseFontSize: CGFloat = 16
    /// Extra leading between lines, in em-relative units. 0.30 puts total
    /// line height at ≈1.5×, which sits in the typography-designer comfort
    /// zone for both prose and technical reading. Reading themes push to
    /// 0.45–0.55 for serif body; operational themes can drop to 0.25.
    var paragraphLineSpacingEm: CGFloat = 0.30
    /// Horizontal padding around the rendered article when not max-width
    /// constrained, or when the window is narrower than `articleMaxWidth`.
    var articleHorizontalPadding: CGFloat = 40
    /// Max width for the article column; the LazyVStack centers when the
    /// window is wider. Default 860pt ≈ 95–100ch at 16pt SF Pro — a
    /// reasonable cap that keeps lines from running edge-to-edge on a
    /// 27" display. Reading themes go narrower (Sevilla → 620);
    /// utility/technical themes go wider (Charcoal → 920).
    var articleMaxWidth: CGFloat? = 860

    // MARK: Heading scale

    /// Heading sizes in em units (relative to body). The MarkdownUI gitHub
    /// scale (2.0 / 1.5 / 1.25) reads as a "designed document"; we tone it
    /// down by default and let weight + spacing carry hierarchy. Themes
    /// can override either way.
    var h1SizeEm: CGFloat = 1.75
    var h2SizeEm: CGFloat = 1.4
    var h3SizeEm: CGFloat = 1.15

    /// Weight applied to h1–h6. Default `.semibold` matches MarkdownUI's
    /// gitHub theme. Themes that bundle a heavy face whose Regular is
    /// already visually weighty (OpenDyslexic, Dyslexie) drop this back to
    /// `.regular` so headings differ from body by size + color + rule
    /// instead of doubling-down on weight.
    var headingFontWeight: Font.Weight = .semibold
    /// Weight applied to in-paragraph `**strong**` runs. Default `.semibold`
    /// matches MarkdownUI's gitHub. Themes whose body face only ships a
    /// Regular and a heavy weight (OpenDyslexic: 400 + 800) can use `.bold`
    /// here to force the bold variant; themes whose semibold reads cleanly
    /// on its own can leave the default.
    var strongFontWeight: Font.Weight = .semibold

    /// H1 keeps a (per-theme-divider-color) rule for orientation. H2 rules
    /// stack visually with the H1 rule and produce "designed document" mass;
    /// off by default. Themes that genuinely want a rule under every
    /// section break can flip it on.
    var showH1Rule: Bool = true
    var showH2Rule: Bool = false

    // MARK: Per-element spacing

    /// Vertical margins around each block, in points. Defaults match
    /// `Theme.gitHub`'s 24/16. Themes that want a tighter operational
    /// rhythm (Charcoal) or more generous reading rhythm (Sevilla) can
    /// override piece-by-piece.
    var paragraphBottomSpacing: CGFloat = 16
    var h1TopSpacing: CGFloat = 24
    var h1BottomSpacing: CGFloat = 16
    var h2TopSpacing: CGFloat = 24
    var h2BottomSpacing: CGFloat = 16
    var h3TopSpacing: CGFloat = 24
    var h3BottomSpacing: CGFloat = 16

    // MARK: Interactive accent

    /// Color for in-viewer interactive affordances that aren't part of the
    /// markdown rendering itself (bookmark-hover stripe, current-block
    /// highlight, etc.). Defaults to the system accent so untouched themes
    /// look native; theme authors can swap in something that doesn't clash
    /// with the palette (Sevilla → terracotta, Charcoal → muted GitHub blue).
    var accent: Color = .accentColor

    // MARK: Code highlighting

    /// Per-theme syntax-highlighting palette. `nil` falls back to a sane
    /// GitHub-Light / One-Dark default picked off `isDark` — see `resolvedCodePalette`.
    var codePalette: CodePalette? = nil

    var resolvedCodePalette: CodePalette {
        codePalette ?? (isDark ? .oneDarkDefault : .githubLightDefault)
    }
}

/// Maps tree-sitter capture names to colors. Slots cover the common
/// `highlights.scm` capture vocabulary (`@keyword`, `@string`, …);
/// unmapped captures fall back to `plain`.
struct CodePalette: Hashable {
    /// Optional override for the code-block background. `nil` means
    /// inherit `MDVTheme.secondaryBackground`.
    let background: Color?

    let plain: Color
    let keyword: Color
    let string: Color
    let number: Color
    let comment: Color
    let type: Color
    let function: Color
    let attribute: Color
    let variable: Color
    let constant: Color
    let operatorColor: Color

    /// Reserved for the line-number gutter (Phase 3).
    let lineNumber: Color
    /// Reserved for the find-current-match line tint (Phase 3).
    let lineHighlight: Color

    /// Reserved for diff blocks (Phase 5).
    let diffAdd: Color
    let diffRemove: Color
    let diffAddBg: Color
    let diffRemoveBg: Color
}

extension CodePalette {
    /// GitHub Light syntax — canonical reference for light themes. Used by
    /// any light theme that doesn't ship its own palette.
    static let githubLightDefault = CodePalette(
        background: nil,
        plain:        Color(rgba: 0x1F2328FF),
        keyword:      Color(rgba: 0xCF222EFF),  // red
        string:       Color(rgba: 0x0A3069FF),  // deep blue
        number:       Color(rgba: 0x0550AEFF),
        comment:      Color(rgba: 0x6E7781FF),  // grey, italic in render
        type:         Color(rgba: 0x953800FF),  // orange-brown
        function:     Color(rgba: 0x8250DFFF),  // purple
        attribute:    Color(rgba: 0x116329FF),  // green
        variable:     Color(rgba: 0x1F2328FF),
        constant:     Color(rgba: 0x0550AEFF),
        operatorColor:Color(rgba: 0xCF222EFF),
        lineNumber:   Color(rgba: 0x8C959FFF),
        lineHighlight:Color(rgba: 0xFFF8C5FF),
        diffAdd:      Color(rgba: 0x1A7F37FF),
        diffRemove:   Color(rgba: 0xCF222EFF),
        diffAddBg:    Color(rgba: 0xDAFBE1FF),
        diffRemoveBg: Color(rgba: 0xFFEBE9FF)
    )

    /// One Dark syntax — canonical reference for dark themes.
    static let oneDarkDefault = CodePalette(
        background: nil,
        plain:        Color(rgba: 0xABB2BFFF),
        keyword:      Color(rgba: 0xC678DDFF),  // purple
        string:       Color(rgba: 0x98C379FF),  // green
        number:       Color(rgba: 0xD19A66FF),  // orange
        comment:      Color(rgba: 0x7F848EFF),
        type:         Color(rgba: 0xE5C07BFF),  // yellow
        function:     Color(rgba: 0x61AFEFFF),  // blue
        attribute:    Color(rgba: 0xD19A66FF),
        variable:     Color(rgba: 0xE06C75FF),  // soft red
        constant:     Color(rgba: 0xD19A66FF),
        operatorColor:Color(rgba: 0xC678DDFF),
        lineNumber:   Color(rgba: 0x636D83FF),
        lineHighlight:Color(rgba: 0x3E4451FF),
        diffAdd:      Color(rgba: 0x98C379FF),
        diffRemove:   Color(rgba: 0xE06C75FF),
        diffAddBg:    Color(rgba: 0x1E3A2BFF),
        diffRemoveBg: Color(rgba: 0x3E1C20FF)
    )

    /// Sevilla — earth-tone palette tuned for the cream/terracotta reading
    /// theme. Lower-saturation than GitHub Light so code stops short of
    /// shouting; the azulejo-blue function color mirrors the theme's link.
    static let sevillaPalette = CodePalette(
        background: nil,
        plain:        Color(rgba: 0x42372CFF),  // = body
        keyword:      Color(rgba: 0x8C2A1AFF),  // deep terracotta
        string:       Color(rgba: 0x5C4030FF),  // walnut
        number:       Color(rgba: 0x7A4A1FFF),  // umber
        comment:      Color(rgba: 0x968874FF),  // = tertiaryText, italic in render
        type:         Color(rgba: 0x7B5C3DFF),  // raw umber
        function:     Color(rgba: 0x2C5F8DFF),  // azulejo blue (= link)
        attribute:    Color(rgba: 0xB0623EFF),  // terracotta (= accent)
        variable:     Color(rgba: 0x42372CFF),
        constant:     Color(rgba: 0x7A4A1FFF),
        operatorColor:Color(rgba: 0x42372CFF),
        lineNumber:   Color(rgba: 0xC0B49AFF),
        lineHighlight:Color(rgba: 0xE6DEC2FF),
        diffAdd:      Color(rgba: 0x4F7138FF),
        diffRemove:   Color(rgba: 0x8C2A1AFF),
        diffAddBg:    Color(rgba: 0xE3E5C9FF),
        diffRemoveBg: Color(rgba: 0xF0DCD0FF)
    )

    /// Charcoal — GitHub-Dark-ish palette. Charcoal is the operational
    /// theme; we want vivid token semantics without compromising Charcoal's
    /// neutral grey-blue chrome. GitHub Dark's actual published palette
    /// reads cleanly against Charcoal's `#1B1B21` and stays well clear of
    /// the muted accent blue used elsewhere in the UI.
    static let charcoalPalette = CodePalette(
        background: nil,
        plain:        Color(rgba: 0xC9D1D9FF),
        keyword:      Color(rgba: 0xFF7B72FF),  // GitHub Dark coral
        string:       Color(rgba: 0xA5D6FFFF),  // light blue
        number:       Color(rgba: 0x79C0FFFF),
        comment:      Color(rgba: 0x8B949EFF),
        type:         Color(rgba: 0xFFA657FF),  // orange
        function:     Color(rgba: 0xD2A8FFFF),  // purple
        attribute:    Color(rgba: 0x7EE787FF),  // green
        variable:     Color(rgba: 0xC9D1D9FF),
        constant:     Color(rgba: 0x79C0FFFF),
        operatorColor:Color(rgba: 0xFF7B72FF),
        lineNumber:   Color(rgba: 0x484F58FF),
        lineHighlight:Color(rgba: 0x2A2F37FF),
        diffAdd:      Color(rgba: 0x7EE787FF),
        diffRemove:   Color(rgba: 0xFF7B72FF),
        diffAddBg:    Color(rgba: 0x0E2B1AFF),
        diffRemoveBg: Color(rgba: 0x3D1416FF)
    )

    /// Solarized Light — Ethan Schoonover's canonical accent assignments.
    /// Green for keywords, cyan for strings, blue for functions, magenta
    /// for numbers. The palette this theme was made for.
    static let solarizedLightPalette = CodePalette(
        background: nil,
        plain:        Color(rgba: 0x586E75FF),  // base01 (= body)
        keyword:      Color(rgba: 0x859900FF),  // green
        string:       Color(rgba: 0x2AA198FF),  // cyan
        number:       Color(rgba: 0xD33682FF),  // magenta
        comment:      Color(rgba: 0x93A1A1FF),  // base1
        type:         Color(rgba: 0xB58900FF),  // yellow
        function:     Color(rgba: 0x268BD2FF),  // blue
        attribute:    Color(rgba: 0xCB4B16FF),  // orange (= accent)
        variable:     Color(rgba: 0x586E75FF),
        constant:     Color(rgba: 0x6C71C4FF),  // violet
        operatorColor:Color(rgba: 0x859900FF),
        lineNumber:   Color(rgba: 0x93A1A1FF),
        lineHighlight:Color(rgba: 0xEEE8D5FF),  // base2
        diffAdd:      Color(rgba: 0x859900FF),
        diffRemove:   Color(rgba: 0xDC322FFF),  // red
        diffAddBg:    Color(rgba: 0xEAE9CDFF),
        diffRemoveBg: Color(rgba: 0xF0D8D2FF)
    )

    /// Solarized Dark — same Solarized accents on the dark base.
    static let solarizedDarkPalette = CodePalette(
        background: nil,
        plain:        Color(rgba: 0x93A1A1FF),  // base1
        keyword:      Color(rgba: 0x859900FF),
        string:       Color(rgba: 0x2AA198FF),
        number:       Color(rgba: 0xD33682FF),
        comment:      Color(rgba: 0x586E75FF),  // base01 (darker for dark bg)
        type:         Color(rgba: 0xB58900FF),
        function:     Color(rgba: 0x268BD2FF),
        attribute:    Color(rgba: 0xCB4B16FF),
        variable:     Color(rgba: 0x93A1A1FF),
        constant:     Color(rgba: 0x6C71C4FF),
        operatorColor:Color(rgba: 0x859900FF),
        lineNumber:   Color(rgba: 0x586E75FF),
        lineHighlight:Color(rgba: 0x073642FF),  // base02
        diffAdd:      Color(rgba: 0x859900FF),
        diffRemove:   Color(rgba: 0xDC322FFF),
        diffAddBg:    Color(rgba: 0x0F2E1AFF),
        diffRemoveBg: Color(rgba: 0x3A1817FF)
    )

    /// Phosphor — monochrome amber with brightness-only differentiation.
    /// CRT vibe: never let green or red sneak in. Tokens read by *weight*
    /// of brightness, not hue.
    static let phosphorPalette = CodePalette(
        background: nil,
        plain:        Color(rgba: 0xF5F5F5FF),  // = body
        keyword:      Color(rgba: 0xFFB84DFF),  // bright amber
        string:       Color(rgba: 0xFFD43BFF),  // yellow (= link)
        number:       Color(rgba: 0xFFAA00FF),
        comment:      Color(rgba: 0x888888FF),
        type:         Color(rgba: 0xFFD080FF),
        function:     Color(rgba: 0xFFA500FF),  // amber (= heading)
        attribute:    Color(rgba: 0xFFC966FF),
        variable:     Color(rgba: 0xF5F5F5FF),
        constant:     Color(rgba: 0xFFAA00FF),
        operatorColor:Color(rgba: 0xF5F5F5FF),
        lineNumber:   Color(rgba: 0x6E5A2EFF),
        lineHighlight:Color(rgba: 0x2A2210FF),
        diffAdd:      Color(rgba: 0xCFCFCFFF),
        diffRemove:   Color(rgba: 0x888888FF),
        diffAddBg:    Color(rgba: 0x1A1A1AFF),
        diffRemoveBg: Color(rgba: 0x141414FF)
    )

    /// Dyslexia Light — restrained palette tuned for the cream/dark-warm
    /// reading themes. Token differentiation kept low-saturation: high-contrast
    /// rainbow palettes pull the eye around the page, which works against the
    /// "calm reading surface" the dyslexia themes optimize for.
    static let dyslexiaLightPalette = CodePalette(
        background: nil,
        plain:        Color(rgba: 0x2C2A26FF),  // = body
        keyword:      Color(rgba: 0x6A4A87FF),  // muted plum
        string:       Color(rgba: 0x2A6A52FF),  // forest teal
        number:       Color(rgba: 0x8A4A1FFF),  // umber
        comment:      Color(rgba: 0x8B8576FF),  // = tertiaryText, italic in render
        type:         Color(rgba: 0x5A5034FF),  // olive
        function:     Color(rgba: 0x1B4F8AFF),  // = link (deep blue)
        attribute:    Color(rgba: 0xB0623EFF),  // = accent (terracotta)
        variable:     Color(rgba: 0x2C2A26FF),
        constant:     Color(rgba: 0x8A4A1FFF),
        operatorColor:Color(rgba: 0x2C2A26FF),
        lineNumber:   Color(rgba: 0xC0B49AFF),
        lineHighlight:Color(rgba: 0xF0E9CFFF),
        diffAdd:      Color(rgba: 0x4F7138FF),
        diffRemove:   Color(rgba: 0x8C2A1AFF),
        diffAddBg:    Color(rgba: 0xE3E5C9FF),
        diffRemoveBg: Color(rgba: 0xF0DCD0FF)
    )

    /// Dyslexia Dark — warm-amber-on-navy palette tuned to match the cream
    /// body color. No greens, no reds — both are common confusion pairs;
    /// the palette stays in a warm-cream / dusty-amber band with a single
    /// muted-blue accent for functions so links/functions don't drift into
    /// the body color.
    static let dyslexiaDarkPalette = CodePalette(
        background: nil,
        plain:        Color(rgba: 0xE5DCC5FF),  // = body
        keyword:      Color(rgba: 0xC99A4AFF),  // muted amber (= accent)
        string:       Color(rgba: 0xD2BD8AFF),  // wheat — distinct from amber via lower saturation
        number:       Color(rgba: 0xE8B270FF),  // soft cream-amber
        comment:      Color(rgba: 0x847C6AFF),  // = tertiaryText, italic in render
        type:         Color(rgba: 0xD2BD8AFF),
        function:     Color(rgba: 0xA8C3E0FF),  // dusty pale blue — only cool note in the palette
        attribute:    Color(rgba: 0xC9846AFF),  // warm peach
        variable:     Color(rgba: 0xE5DCC5FF),
        constant:     Color(rgba: 0xE8B270FF),
        operatorColor:Color(rgba: 0xE5DCC5FF),
        lineNumber:   Color(rgba: 0x52596CFF),
        lineHighlight:Color(rgba: 0x252D40FF),
        diffAdd:      Color(rgba: 0xC9C19AFF),  // brightness, not green
        diffRemove:   Color(rgba: 0x847C6AFF),  // brightness, not red
        diffAddBg:    Color(rgba: 0x222B1AFF),
        diffRemoveBg: Color(rgba: 0x2A211AFF)
    )

    /// Twilight — pastel palette matching the cool navy bg + mint heading
    /// + cream link. Low saturation throughout.
    static let twilightPalette = CodePalette(
        background: nil,
        plain:        Color(rgba: 0xB0B5BCFF),  // = body
        keyword:      Color(rgba: 0xF8B3B0FF),  // soft pink-cream
        string:       Color(rgba: 0xA6E3B0FF),  // soft mint (in same family as the heading)
        number:       Color(rgba: 0xFBD78DFF),  // warm cream
        comment:      Color(rgba: 0x5B6168FF),  // = tertiaryText
        type:         Color(rgba: 0xFFD580FF),  // cream (= link)
        function:     Color(rgba: 0xA8C9F0FF),  // soft pastel blue
        attribute:    Color(rgba: 0xC8B5E8FF),  // lilac
        variable:     Color(rgba: 0xB0B5BCFF),
        constant:     Color(rgba: 0xFBD78DFF),
        operatorColor:Color(rgba: 0xF8B3B0FF),
        lineNumber:   Color(rgba: 0x3F454CFF),
        lineHighlight:Color(rgba: 0x1A2129FF),
        diffAdd:      Color(rgba: 0xA6E3B0FF),
        diffRemove:   Color(rgba: 0xF8B3B0FF),
        diffAddBg:    Color(rgba: 0x122319FF),
        diffRemoveBg: Color(rgba: 0x271419FF)
    )
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
        let pBottom = self.paragraphBottomSpacing
        let h1Top = self.h1TopSpacing
        let h1Bottom = self.h1BottomSpacing
        let h2Top = self.h2TopSpacing
        let h2Bottom = self.h2BottomSpacing
        let h3Top = self.h3TopSpacing
        let h3Bottom = self.h3BottomSpacing
        let headWeight = self.headingFontWeight
        let strongWeight = self.strongFontWeight

        return Theme()
            .text {
                FontFamily(family)
                ForegroundColor(txt)
                BackgroundColor(bg)
                FontSize(bodySize)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.90))                     // up from 0.85 — inline code at body × 0.85 reads small next to a serif body and at our usual sans body sizes
                BackgroundColor(sbg)
            }
            .strong {
                FontWeight(strongWeight)
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
                        .markdownMargin(top: h1Top, bottom: h1Bottom)
                        .markdownTextStyle {
                            FontWeight(headWeight)
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
                        .markdownMargin(top: h2Top, bottom: h2Bottom)
                        .markdownTextStyle {
                            FontWeight(headWeight)
                            FontSize(.em(h2))
                            ForegroundColor(head)
                        }
                    if h2Rule { Divider().overlay(div) }
                }
            }
            .heading3 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: h3Top, bottom: h3Bottom)
                    .markdownTextStyle {
                        FontWeight(headWeight)
                        FontSize(.em(h3))
                        ForegroundColor(head)
                    }
            }
            .heading4 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(headWeight)
                        ForegroundColor(head)
                    }
            }
            .heading5 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(headWeight)
                        FontSize(.em(0.875))
                        ForegroundColor(head)
                    }
            }
            .heading6 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(headWeight)
                        FontSize(.em(0.85))
                        ForegroundColor(ttxt)
                    }
            }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(lineEm))
                    .markdownMargin(top: 0, bottom: pBottom)
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
                // CodeBlockChrome owns the scroll/wrap container, the
                // language label, the hover toolbar, and the right-click
                // menu. Font + colors are set inside MDVCodeSyntaxHighlighter —
                // the configuration.label here is the Text we produced and we
                // don't apply markdownTextStyle font/size on top of it.
                CodeBlockChrome(configuration: configuration, theme: self)
                    .markdownMargin(top: 0, bottom: 16)
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.25))
            }
            .taskListMarker { configuration in
                // Quieter than MarkdownUI's gitHub default (Color.checkbox /
                // Color.checkboxBackground), but checked vs unchecked has to
                // remain legible at a glance. Checked: filled square at body
                // color, opacity .75. Unchecked: empty square at tertiary
                // color, opacity .40. The opacity + color delta does the
                // distinguishing work, not the SF Symbol shape alone.
                if configuration.isCompleted {
                    Image(systemName: "checkmark.square.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(txt.opacity(0.75))
                        .baselineOffset(1)
                        .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
                } else {
                    Image(systemName: "square")
                        .font(.system(size: 12.5))
                        .foregroundStyle(ttxt.opacity(0.40))
                        .baselineOffset(1)
                        .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
                }
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
        strong: Color(rgba: 0x0A0A0AFF),              // tier 1 (= body); SF Pro semibold pops on white without needing the lift
        border: Color(rgba: 0xE5E7EBFF),
        divider: Color(rgba: 0xD1D5DBFF),
        blockquoteBar: Color(rgba: 0xD1D5DBFF),
        sidebarTint: Color(rgba: 0xFFFFFFFF),
        sidebarTintOpacity: 0.0,
        accent: Color(rgba: 0x1D6FE0FF),              // = link — High Contrast leans into system-blue territory
        codePalette: .githubLightDefault              // GitHub Light syntax: blue keywords, deep-blue strings, grey italic comments
    )

    /// "GitHub README, dark, all business" — compact, neutral, high density.
    /// Tuned for technical reading (READMEs, internal docs), not long-form
    /// prose. See TYPOGRAPHY.md → Charcoal section for the rationale.
    /// "GitHub README, dark, all business" — compact, neutral, high density.
    /// Tuned for technical reading (READMEs, internal docs), not long-form
    /// prose. See TYPOGRAPHY.md → Charcoal section for the rationale.
    static let charcoal = MDVTheme(
        id: "charcoal",
        name: "Charcoal",
        isDark: true,
        background: Color(rgba: 0x1B1B21FF),          // cooler, slightly darker than v1 (#1E1F25); per user spec rgb(0.105, 0.106, 0.128)
        secondaryBackground: Color(rgba: 0x25262CFF), // pulled closer to bg — inline-code pills no longer read like selected text. Was #2E303B.
        text: Color(rgba: 0xC7D1DBFF),                // muted cool-grey body — leaves headroom above
        secondaryText: Color(rgba: 0x8C99A8FF),
        tertiaryText: Color(rgba: 0x6E7785FF),
        heading: Color(rgba: 0xF5F7FCFF),             // not pure white — reserves max brightness
        link: Color(rgba: 0x5CA3FAFF),                // GitHub-style blue; less saturated than #6FB1FF
        strong: Color(rgba: 0xE8EDF5FF),              // tier 2 (body < strong < heading). Slightly dimmer than v1 #EBF0F7; the previous value sat too close to heading and made every `**bold**` mid-paragraph feel shouty.
        border: Color(rgba: 0x3B4252FF),
        divider: Color(rgba: 0x3B4252FF),
        blockquoteBar: Color(rgba: 0x3B4252FF),       // neutral grey rule, not accent-blue
        sidebarTint: Color(rgba: 0x1B1B21FF),
        sidebarTintOpacity: 0.18,
        baseFontSize: 16.5,                           // half-pt nudge for crisper SF Pro at this column width
        paragraphLineSpacingEm: 0.25,                 // ≈1.46× — operational, not literary
        articleHorizontalPadding: 48,                 // was 40 — per user spec; gives the page a real left/right margin
        articleMaxWidth: 920,                         // wider measure than reading themes — technical docs scan better wider
        h1SizeEm: 1.82,                               // = 30pt at 16.5 body
        h2SizeEm: 1.45,                               // = 24pt — per user spec
        h3SizeEm: 1.15,                               // = 19pt
        showH1Rule: true,                             // faded rule under H1 for orientation
        showH2Rule: false,                            // drop H2 rule
        // Operational rhythm — tighter spacing for technical docs.
        paragraphBottomSpacing: 11,
        h1TopSpacing: 0,
        h1BottomSpacing: 12,                          // was 14 — per user spec
        h2TopSpacing: 22,                             // was 26 — per user spec
        h2BottomSpacing: 13,                          // was 10 — per user spec
        h3TopSpacing: 18,
        h3BottomSpacing: 8,
        accent: Color(rgba: 0x2E7AEBFF),              // muted GitHub blue — calmer than system .accentColor for in-viewer affordances
        codePalette: .charcoalPalette                 // GitHub Dark — vivid token semantics against the cool grey-blue chrome
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
        strong: Color(rgba: 0x586E75FF),      // tier 1 (= body); the olive-grey body is muted enough that semibold weight reads cleanly without lifting toward the dark-base02 heading
        border: Color(rgba: 0xDED7C2FF),
        divider: Color(rgba: 0xDED7C2FF),
        blockquoteBar: Color(rgba: 0xCB4B16FF), // orange — accents the bar
        sidebarTint: Color(rgba: 0xFDF6E3FF),
        sidebarTintOpacity: 0.55,
        accent: Color(rgba: 0xCB4B16FF),       // Solarized orange — the warm accent is more interesting than another blue
        codePalette: .solarizedLightPalette    // canonical Schoonover accents — the palette this theme exists for
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
        showH2Rule: false,                            // remove H2 rule — too heavy in long-form
        // Reading rhythm — slightly more generous spacing than Charcoal's operational rhythm.
        paragraphBottomSpacing: 14,
        h1TopSpacing: 28,
        h1BottomSpacing: 18,
        h2TopSpacing: 32,
        h2BottomSpacing: 12,
        h3TopSpacing: 22,
        h3BottomSpacing: 8,
        accent: Color(rgba: 0xB0623EFF),              // terracotta — the warm accent for in-viewer affordances (bookmark-hover stripe etc.)
        codePalette: .sevillaPalette                  // earth-tones — calm, lower-saturation, function color borrows the link's azulejo blue
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
        strong: Color(rgba: 0xC5CDC2FF),      // tier 2 (between body base1 and heading base2); was #FDF6E3 (= base3), too close to heading
        border: Color(rgba: 0x0E4753FF),
        divider: Color(rgba: 0x0E4753FF),
        blockquoteBar: Color(rgba: 0xB58900FF), // yellow accent
        sidebarTint: Color(rgba: 0x002B36FF),
        sidebarTintOpacity: 0.32,
        accent: Color(rgba: 0xB58900FF),       // Solarized yellow — matches the blockquoteBar; warm against the cool base03 bg
        codePalette: .solarizedDarkPalette     // same Solarized accents on the base03 dark base
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
        strong: Color(rgba: 0xF5F5F5FF),  // tier 1 (= body); the amber heading is doing all the visual work, body bold doesn't need to compete
        border: Color(rgba: 0x2A2A2AFF),
        divider: Color(rgba: 0x2A2A2AFF),
        blockquoteBar: Color(rgba: 0xFFA500FF),
        sidebarTint: Color(rgba: 0x000000FF),
        sidebarTintOpacity: 0.30,
        accent: Color(rgba: 0xFFA500FF),  // amber — leans into the CRT vibe
        codePalette: .phosphorPalette     // monochrome amber, brightness-only differentiation. No green or red.
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
        strong: Color(rgba: 0xD8DEE9FF),  // tier 2 (between body cool-grey and the mint heading); leaves emphasis hue-neutral instead of borrowing mint
        border: Color(rgba: 0x1E252DFF),
        divider: Color(rgba: 0x1E252DFF),
        blockquoteBar: Color(rgba: 0x6EBA7FFF),
        sidebarTint: Color(rgba: 0x0A0F14FF),
        sidebarTintOpacity: 0.32,
        accent: Color(rgba: 0xFFD580FF),  // cream — the warm side of the palette, matches the link
        codePalette: .twilightPalette     // pastels: pink-cream keywords, soft mint strings, lilac attributes — matches the navy/mint/cream palette
    )

    /// Light-mode theme whose core feature is the typeface: bundles
    /// **OpenDyslexic** (FOSS, Abbie Gonzalez) and falls back to the user's
    /// system-installed **Dyslexie** (Christian Boer) when present. Both
    /// share the weighted-glyph-bottom design that anchors letters and
    /// resists the perceived flipping of similar letterforms.
    ///
    /// Typography lives at the cross-theme defaults — same measure, leading,
    /// heading scale, and rhythm as High Contrast or Solarized Light. The
    /// font is the entire point; everything else stays out of its way.
    ///
    /// **Two weight overrides are required for OpenDyslexic.** Its Regular is
    /// already heavy by design (weighted glyph bottoms), and its only other
    /// upright weight is OS/2 usWeightClass **800** (declared as ExtraBold).
    /// MarkdownUI's default `.semibold` heading weight resolves to that 800
    /// ExtraBold — every heading then reads as a wall of bold. The theme
    /// forces `headingFontWeight = .regular` so headings differ from body
    /// only by size + color + rule, and `strongFontWeight = .bold` so
    /// `**emphasis**` runs explicitly request the heavy variant for the
    /// places where weight contrast actually matters.
    /// See TYPOGRAPHY.md → Standard Erin for the rationale.
    static let standardErinLight = MDVTheme(
        id: "standard-erin-light",
        name: "Standard Erin Light",
        isDark: false,
        background: Color(rgba: 0xFBF7E8FF),          // warm cream — gentler than pure white but still standard-density
        secondaryBackground: Color(rgba: 0xF0EAD3FF), // deeper cream for code blocks / table stripes
        text: Color(rgba: 0x2C2A26FF),                // warm dark — not pure black
        secondaryText: Color(rgba: 0x5C584FFF),
        tertiaryText: Color(rgba: 0x8B8576FF),
        heading: Color(rgba: 0x1A1814FF),
        link: Color(rgba: 0x1B4F8AFF),                // deep blue
        strong: Color(rgba: 0x2C2A26FF),              // tier 1 (= body); OpenDyslexic-Bold is the visual lift
        border: Color(rgba: 0xE0D8BEFF),
        divider: Color(rgba: 0xE0D8BEFF),
        blockquoteBar: Color(rgba: 0xB0623EFF),       // terracotta accent
        sidebarTint: Color(rgba: 0xFBF7E8FF),
        sidebarTintOpacity: 0.55,
        bodyFontFamily: .custom(FontRegistration.dyslexiaBodyFamily),
        baseFontSize: 15,                             // one step under the 16pt default — OpenDyslexic's x-height is large enough that 15pt reads ≈16pt SF; pulls the page back from looking outsized
        // Other typography knobs intentionally left at cross-theme defaults.
        // The font is the theme.
        headingFontWeight: .regular,                  // see doc-comment above — OpenDyslexic only ships 400 + 800
        strongFontWeight: .bold,                      // explicit so **emphasis** picks up the 800 variant
        accent: Color(rgba: 0xB0623EFF),              // terracotta
        codePalette: .dyslexiaLightPalette
    )

    /// Dark variant of Standard Erin. Same family resolution + same weight
    /// overrides as the light variant; defaults-everywhere typography. Deep
    /// navy bg (not pure black) with warm cream text (not pure white) —
    /// matches the light variant's choice to stay out of pure-value
    /// territory without inflating leading or measure.
    static let standardErinDark = MDVTheme(
        id: "standard-erin-dark",
        name: "Standard Erin Dark",
        isDark: true,
        background: Color(rgba: 0x1B2233FF),          // deep navy — not pure black
        secondaryBackground: Color(rgba: 0x252D40FF), // raised navy for code blocks / table stripes
        text: Color(rgba: 0xE5DCC5FF),                // warm cream — not pure white
        secondaryText: Color(rgba: 0xB0A88FFF),
        tertiaryText: Color(rgba: 0x847C6AFF),
        heading: Color(rgba: 0xF0E8CFFF),
        link: Color(rgba: 0xF5C97AFF),                // warm amber
        strong: Color(rgba: 0xE5DCC5FF),              // tier 1 (= body)
        border: Color(rgba: 0x2E3A50FF),
        divider: Color(rgba: 0x2E3A50FF),
        blockquoteBar: Color(rgba: 0xC99A4AFF),       // dusty amber accent
        sidebarTint: Color(rgba: 0x1B2233FF),
        sidebarTintOpacity: 0.32,
        bodyFontFamily: .custom(FontRegistration.dyslexiaBodyFamily),
        baseFontSize: 15,
        headingFontWeight: .regular,
        strongFontWeight: .bold,
        accent: Color(rgba: 0xC99A4AFF),
        codePalette: .dyslexiaDarkPalette
    )

    static let all: [MDVTheme] = [
        .highContrast,
        .sevilla,
        .charcoal,
        .solarizedLight,
        .solarizedDark,
        .phosphor,
        .twilight,
        .standardErinLight,
        .standardErinDark,
    ]

    static let `default`: MDVTheme = .highContrast

    static func byID(_ id: String) -> MDVTheme {
        all.first(where: { $0.id == id }) ?? .default
    }
}

// MARK: - ThemeManager

/// Owns the user's current theme choice. Backed by `@AppStorage` so the
/// last-selected theme persists across launches without any explicit save.
///
/// `selectedID` is what the user picked, which may be the special
/// `systemID` sentinel meaning "follow the macOS appearance"; `current`
/// is always a concrete theme. When the user is on `systemID` we KVO
/// `NSApp.effectiveAppearance` so a system Light↔Dark switch reflows the
/// document immediately.
final class ThemeManager: ObservableObject {
    /// Sentinel selection meaning "follow the system appearance". Resolves
    /// to High Contrast in light mode, Twilight in dark.
    static let systemID = "system"

    /// Display name for the synthetic System entry in the theme picker.
    static let systemDisplayName = "System"

    @AppStorage("mdv_theme_id") private var storedID: String = MDVTheme.default.id

    /// What the user picked — may be `systemID`. Use this for menu
    /// checkmarks; use `current` for actual rendering.
    @Published private(set) var selectedID: String = MDVTheme.default.id
    @Published var current: MDVTheme = .default

    private var appearanceObservation: NSKeyValueObservation?

    init() {
        self.selectedID = storedID
        self.current = Self.resolve(id: storedID)
        // KVO on effectiveAppearance: the OS posts when the user toggles
        // dark mode, when scheduled night-shift fires, or when the
        // appearance is forced on a per-window basis. We only re-resolve
        // when the user's selection is "system" — explicit picks are sticky.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            DispatchQueue.main.async { self.systemAppearanceChanged() }
        }
    }

    /// Pick a concrete theme. Use `setSelection(_:)` with `systemID` for
    /// the follow-the-system option.
    func set(_ theme: MDVTheme) {
        setSelection(theme.id)
    }

    func setSelection(_ id: String) {
        selectedID = id
        storedID = id
        current = Self.resolve(id: id)
    }

    private func systemAppearanceChanged() {
        guard selectedID == Self.systemID else { return }
        let resolved = Self.resolve(id: Self.systemID)
        if resolved.id != current.id { current = resolved }
    }

    private static func resolve(id: String) -> MDVTheme {
        if id == systemID {
            return systemIsDark() ? .twilight : .highContrast
        }
        return MDVTheme.byID(id)
    }

    private static func systemIsDark() -> Bool {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua
    }
}
