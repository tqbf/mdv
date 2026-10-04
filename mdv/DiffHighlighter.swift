import AppKit
import Foundation
import SwiftUI

/// Line-level colouring for ` ```diff ` / ` ```patch ` fenced blocks.
///
/// Tree-sitter isn't used here: a unified diff is classified line by line
/// from its prefix column, and hunk headers carry the line counts needed
/// to tell a removed `-- comment` line (`--- comment`) from a `--- a/file`
/// header. Added and removed lines get the palette's diff foreground and
/// background; the `+` / `-` column stays visible.
enum DiffHighlighter {
    /// Fence info words rendered as a diff.
    static let fenceWords: Set<String> = ["diff", "patch"]

    enum LineKind: Equatable {
        case meta        // `diff --git`, `index`, `---` / `+++`, commit headers
        case hunkHeader  // `@@ -a,b +c,d @@`
        case added
        case removed
        case context
        case note        // `\ No newline at end of file`
    }

    /// Classify each line. Inside a hunk the header's counts decide where
    /// the body ends; outside one, `+` / `-` lines still count as changes
    /// so hand-written snippets without `@@` headers colour too.
    static func classify(_ lines: [Substring]) -> [LineKind] {
        var oldLeft = 0
        var newLeft = 0
        return lines.map { line in
            if oldLeft > 0 || newLeft > 0 {
                switch line.first {
                case "+":  newLeft -= 1; return .added
                case "-":  oldLeft -= 1; return .removed
                case "\\": return .note
                default:   oldLeft -= 1; newLeft -= 1; return .context  // " " or a stripped blank line
                }
            }
            if let counts = hunkCounts(line) {
                (oldLeft, newLeft) = counts
                return .hunkHeader
            }
            if line.hasPrefix("--- ") || line.hasPrefix("+++ ") { return .meta }
            switch line.first {
            case "+":       return .added
            case "-":       return .removed
            case "\\":      return .note
            case " ", nil:  return .context
            default:        return .meta
            }
        }
    }

    /// Old and new line counts from `@@ -l[,s] +l[,s] @@`; an omitted
    /// count means one line.
    static func hunkCounts(_ line: Substring) -> (old: Int, new: Int)? {
        let fields = line.split(separator: " ", maxSplits: 3)
        guard fields.count >= 3, fields[0] == "@@",
              fields[1].hasPrefix("-"), fields[2].hasPrefix("+") else { return nil }
        func count(_ range: Substring) -> Int? {
            let parts = range.dropFirst().split(separator: ",", omittingEmptySubsequences: false)
            guard (1...2).contains(parts.count), parts.allSatisfy({ Int($0) != nil }) else { return nil }
            return parts.count == 2 ? Int(parts[1]) : 1
        }
        guard let old = count(fields[1]), let new = count(fields[2]) else { return nil }
        return (old, new)
    }

    static func render(
        code: String,
        palette: CodePalette,
        hunkHeaderColor: Color,
        fontSize: CGFloat
    ) -> AttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let boldMono = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let italicMono = NSFontManager.shared.convert(mono, toHaveTrait: .italicFontMask)

        let nsAttr = NSMutableAttributedString(string: code)
        nsAttr.addAttribute(.font, value: mono, range: NSRange(location: 0, length: nsAttr.length))
        nsAttr.addAttribute(.foregroundColor, value: NSColor(palette.plain),
                            range: NSRange(location: 0, length: nsAttr.length))

        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        for (line, kind) in zip(lines, classify(lines)) {
            let range = NSRange(line.startIndex..<line.endIndex, in: code)
            switch kind {
            case .added:
                nsAttr.addAttribute(.foregroundColor, value: NSColor(palette.diffAdd), range: range)
                nsAttr.addAttribute(.backgroundColor, value: NSColor(palette.diffAddBg), range: range)
            case .removed:
                nsAttr.addAttribute(.foregroundColor, value: NSColor(palette.diffRemove), range: range)
                nsAttr.addAttribute(.backgroundColor, value: NSColor(palette.diffRemoveBg), range: range)
            case .hunkHeader:
                nsAttr.addAttribute(.foregroundColor, value: NSColor(hunkHeaderColor), range: range)
                nsAttr.addAttribute(.font, value: italicMono, range: range)
            case .meta:
                nsAttr.addAttribute(.font, value: boldMono, range: range)
            case .note:
                nsAttr.addAttribute(.foregroundColor, value: NSColor(palette.comment), range: range)
                nsAttr.addAttribute(.font, value: italicMono, range: range)
            case .context:
                break
            }
        }
        return AttributedString(nsAttr)
    }
}
