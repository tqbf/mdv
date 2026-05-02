import Foundation

/// Apply SmartyPants-style typography to a chunk of markdown source:
///
/// - Straight `"` and `'` curl into directional quotes (`"` `"` `'` `'`),
///   choosing open vs. close from preceding-character context.
/// - `---` becomes an em-dash (—). `--` between digits or letters becomes
///   an en-dash (–). ` -- ` (space-dashdash-space) becomes a spaced em-dash.
///   Other `--` runs are left alone so CLI flags (`--option`) survive.
/// - `...` becomes a horizontal ellipsis (…).
///
/// Code is not touched: inline backtick spans `` `like this` `` and fenced
/// code blocks (` ``` ` / `~~~`) are preserved verbatim, including any
/// quote, dash, or dot characters inside them. Link URLs `](...)` and
/// autolink / HTML tag spans `<...>` are similarly left as-is.
///
/// The function is meant to run on a *single block* of markdown — call
/// site is `blockView` in ContentView, where blocks are already separated
/// by the fence-aware splitter. The same backtick-run tracking handles
/// inline spans within prose blocks.
func smartenMarkdown(_ source: String) -> String {
    // Whole-block fenced code: nothing to smarten. Cheap early-exit.
    let trimmed = source.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
        return source
    }

    var result = ""
    result.reserveCapacity(source.count)

    var i = source.startIndex
    // Run length of the currently-open inline code span, or 0 if outside.
    // Markdown inline code closes on a backtick run of *exactly* the same
    // length as the opener — `` ``foo`` `` has a 2-backtick fence, etc.
    var codeRun = 0
    // Inside `](...)` URL portion of a link/image. Track paren depth so a
    // URL containing `(` like `https://en.wikipedia.org/wiki/Foo_(disambig)`
    // doesn't close early.
    var linkParenDepth = 0

    while i < source.endIndex {
        let c = source[i]

        // ---- Backtick runs (inline code spans) ----
        if c == "`" {
            var run = 0
            var j = i
            while j < source.endIndex && source[j] == "`" {
                run += 1
                j = source.index(after: j)
            }
            if codeRun == 0 {
                codeRun = run
            } else if codeRun == run {
                codeRun = 0
            }
            // Either way, emit the literal backticks.
            result.append(String(repeating: "`", count: run))
            i = j
            continue
        }

        if codeRun > 0 {
            result.append(c)
            i = source.index(after: i)
            continue
        }

        // ---- Link URL: `](...)` ----
        if linkParenDepth == 0,
           c == "]",
           let next = source.index(i, offsetBy: 1, limitedBy: source.endIndex),
           next < source.endIndex,
           source[next] == "(" {
            result.append("](")
            i = source.index(i, offsetBy: 2)
            linkParenDepth = 1
            continue
        }
        if linkParenDepth > 0 {
            result.append(c)
            if c == "(" { linkParenDepth += 1 }
            else if c == ")" {
                linkParenDepth -= 1
            }
            i = source.index(after: i)
            continue
        }

        // ---- Autolink / HTML tag: `<...>` ----
        // Only treat as opaque when it really looks like a tag/autolink:
        // the first char after `<` must be a letter or `/`. That keeps
        // prose like "x < y" or "<3" working.
        if c == "<",
           let inside = source.index(i, offsetBy: 1, limitedBy: source.endIndex),
           inside < source.endIndex {
            let firstInside = source[inside]
            if firstInside.isLetter || firstInside == "/" {
                // Cap the lookahead so we don't run away on unmatched `<`.
                let limit = source.index(i, offsetBy: 256, limitedBy: source.endIndex) ?? source.endIndex
                if let close = source.range(of: ">", range: i..<limit)?.lowerBound {
                    let endIncl = source.index(after: close)
                    result.append(contentsOf: source[i..<endIncl])
                    i = endIncl
                    continue
                }
            }
        }

        // ---- Em-dash: --- ----
        if c == "-",
           let a1 = source.index(i, offsetBy: 1, limitedBy: source.endIndex), a1 < source.endIndex, source[a1] == "-",
           let a2 = source.index(i, offsetBy: 2, limitedBy: source.endIndex), a2 < source.endIndex, source[a2] == "-" {
            result.append("\u{2014}")
            i = source.index(i, offsetBy: 3)
            continue
        }

        // ---- En-dash / em-dash: -- ----
        if c == "-",
           let a1 = source.index(i, offsetBy: 1, limitedBy: source.endIndex), a1 < source.endIndex, source[a1] == "-" {
            let prev = (i > source.startIndex) ? source[source.index(before: i)] : nil
            let next2: Character? = {
                guard let a2 = source.index(i, offsetBy: 2, limitedBy: source.endIndex), a2 < source.endIndex else { return nil }
                return source[a2]
            }()

            let prevDigit = prev?.isNumber ?? false
            let prevLetter = prev?.isLetter ?? false
            let prevSpace = prev == " "
            let nextDigit = next2?.isNumber ?? false
            let nextLetter = next2?.isLetter ?? false
            let nextSpace = next2 == " "

            if (prevDigit && nextDigit) || (prevLetter && nextLetter) {
                // "1989--2026" or "Foo--Bar" — range-style en-dash.
                result.append("\u{2013}")
                i = source.index(i, offsetBy: 2)
                continue
            }
            if prevSpace && nextSpace {
                // "word -- word" — em-dash. Surrounding spaces preserved.
                result.append("\u{2014}")
                i = source.index(i, offsetBy: 2)
                continue
            }
            // Anything else (e.g. "--flag" at start, or "x--", "--x") is
            // left as raw hyphens so CLI examples don't get mangled.
            result.append("-")
            i = source.index(after: i)
            continue
        }

        // ---- Ellipsis: ... ----
        if c == ".",
           let a1 = source.index(i, offsetBy: 1, limitedBy: source.endIndex), a1 < source.endIndex, source[a1] == ".",
           let a2 = source.index(i, offsetBy: 2, limitedBy: source.endIndex), a2 < source.endIndex, source[a2] == "." {
            result.append("\u{2026}")
            i = source.index(i, offsetBy: 3)
            continue
        }

        // ---- Quote curling ----
        if c == "\"" {
            let prev = (i > source.startIndex) ? source[source.index(before: i)] : nil
            result.append(isOpenQuoteContext(prev) ? "\u{201C}" : "\u{201D}")
            i = source.index(after: i)
            continue
        }
        if c == "'" {
            let prev = (i > source.startIndex) ? source[source.index(before: i)] : nil
            result.append(isOpenQuoteContext(prev) ? "\u{2018}" : "\u{2019}")
            i = source.index(after: i)
            continue
        }

        result.append(c)
        i = source.index(after: i)
    }

    return result
}

/// True if the character preceding a `"` or `'` puts us in "opening quote"
/// position. Used by quote curling. The list is the SmartyPants-standard
/// set of openers (whitespace, start of string, opening brackets, dashes,
/// ellipsis) plus a few unicode quote cousins so back-to-back constructs
/// like `…"` or `—"` open correctly.
private func isOpenQuoteContext(_ prev: Character?) -> Bool {
    guard let p = prev else { return true }
    if p.isWhitespace { return true }
    return "([{<\u{2014}\u{2013}\u{2026}".contains(p)
}
