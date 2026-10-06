import MarkdownUI
import SwiftUI

/// A document's metadata header, laid out as a two-column properties table.
///
/// The styling deliberately mirrors the GFM table styling in `markdownTheme`
/// — same border color, same alternating row fills, same 6/13 cell padding —
/// so a header and a table in the same document read as siblings instead of
/// two unrelated boxes. Every color comes from `MDVTheme`, which is what
/// makes all themes, light and dark, correct without a case for each.
///
/// Values render as plain `Text`, never through `Markdown`: metadata is
/// data, and a `**` or a `#` inside a value belongs to the value.
struct FrontmatterTableView: View {
    let rows: [FrontmatterRow]
    let theme: MDVTheme
    let fontScale: CGFloat

    /// Cell padding, taken from the GFM table cell style.
    private static let hPadding: CGFloat = 13
    private static let vPadding: CGFloat = 6

    /// Width of the key column: the widest key at its natural, unwrapped,
    /// padded width. Nil until the first layout pass reports one, which is
    /// the one pass where keys are still only as wide as themselves.
    @State private var keyColumnWidth: CGFloat?

    var body: some View {
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if let key = row.key {
                        HStack(alignment: .top, spacing: 0) {
                            keyCell(key, row: index)
                            valueCell(row.value, row: index)
                        }
                    } else {
                        valueCell(row.value, row: index)
                    }
                }
            }
            // Assigned, never accumulated: the preference is reduced afresh
            // on every pass, so a document with narrower keys shrinks the
            // column back down instead of inheriting the old maximum.
            .onPreferenceChange(KeyColumnWidth.self) { width in
                keyColumnWidth = width > 0 ? width : nil
            }
            // Keeps the table at its ideal height inside the scrolling
            // column while still letting values wrap, as the table block
            // style does.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The key half of a row. The text is measured at its own natural width
    /// and only then stretched to the column width, so the fill and the
    /// border cover the whole column and the row's band runs unbroken from
    /// one cell into the next.
    ///
    /// `fixedSize` is what keeps the measurement out of its own feedback
    /// loop: the probe reports the key's intrinsic width no matter what
    /// width is proposed, so widening the cell cannot change the number
    /// that decided the widening.
    private func keyCell(_ key: String, row: Int) -> some View {
        Text(key)
            .font(font(weight: .semibold))
            .foregroundStyle(theme.text)
            .lineSpacing(round(bodySize * 0.25))
            .padding(.horizontal, Self.hPadding)
            .fixedSize()
            .background(widthProbe)
            .frame(width: keyColumnWidth, alignment: .topLeading)
            .padding(.vertical, Self.vPadding)
            .modifier(CellBand(fill: fill(row), border: theme.border))
    }

    /// The value half of a row, and the whole of a keyless one: takes the
    /// width the key column leaves and wraps within it.
    private func valueCell(_ value: String, row: Int) -> some View {
        Text(value)
            .font(font())
            .foregroundStyle(theme.text)
            .lineSpacing(round(bodySize * 0.25))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, Self.vPadding)
            .padding(.horizontal, Self.hPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .modifier(CellBand(fill: fill(row), border: theme.border))
    }

    /// Publishes the width of whatever it backs.
    private var widthProbe: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: KeyColumnWidth.self, value: geometry.size.width)
        }
    }

    private func fill(_ row: Int) -> Color {
        row.isMultiple(of: 2) ? theme.background : theme.secondaryBackground
    }

    /// Body size resolved the way MarkdownUI resolves it, so metadata sits on
    /// the same type scale as the prose under it.
    private var bodySize: CGFloat { round(theme.baseFontSize * fontScale) }

    /// The theme's body face at body size — a bundled family for the reading
    /// themes, the system face otherwise. `fixedSize` matches MarkdownUI's own
    /// custom-font resolution, which opts out of Dynamic Type in favor of the
    /// viewer's own zoom.
    private func font(weight: Font.Weight = .regular) -> Font {
        let base: Font
        switch theme.bodyFontFamily {
        case .system(let design):
            base = .system(size: bodySize, design: design)
        case .custom(let name):
            base = .custom(name, fixedSize: bodySize)
        }
        return weight == .regular ? base : base.weight(weight)
    }
}

/// The widest key in the table, in points.
private struct KeyColumnWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Fill and outline for one cell, stretched to the full height of its row so
/// that a value wrapping onto a second line does not leave the key beside it
/// with a short band.
private struct CellBand: ViewModifier {
    let fill: Color
    let border: Color

    func body(content: Content) -> some View {
        content
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(fill)
            .overlay(Rectangle().strokeBorder(border, lineWidth: 1))
    }
}
