import Foundation

/// A metadata header found at the head of a document, located as a single
/// span of the original source.
struct FrontmatterSpan {
    /// The header including both fence lines, with no trailing newline —
    /// byte-identical to what the document's blank-line block splitter
    /// produces for a header with no blank lines of its own, so block
    /// content fingerprints (bookmarks) and block indices (scroll
    /// restoration) are unchanged for the common case.
    let block: String

    /// Index into the original string of the first character after the
    /// closing fence's line break; `endIndex` when the closing fence is
    /// the last line of the file. Always on a `Character` boundary.
    let bodyStart: String.Index
}

/// Locate a metadata header at the very top of `raw`: YAML between `---`
/// fences (or ended by YAML's `...` document terminator), or TOML between
/// `+++` fences. Returns nil when there isn't one.
///
/// The header has to be recognized before markdown parsing because
/// CommonMark has its own reading of it: the opening `---` is a thematic
/// break, the metadata lines are a paragraph, and the closing `---` then
/// underlines that paragraph as a setext heading. Handing the whole header
/// back as one span lets the caller keep it intact as a single block, no
/// matter how many blank lines sit inside it.
///
/// Recognition is deliberately narrow:
///
/// - **Byte 0 only.** Line 1 must be the opening fence and nothing else —
///   no leading or trailing spaces, no blank line above it. Every
///   frontmatter consumer requires this, and it is what stops a `---` in
///   the middle of a document from being read as metadata.
/// - **Exact closers.** A closing fence is a line that is *exactly* `---`
///   or `...` (YAML) or `+++` (TOML), so an indented `  ---` inside a
///   folded value does not end the header. No closer anywhere → not
///   frontmatter.
/// - **Content guard, YAML only.** `---` is also a legal thematic break,
///   so a document that opens with a horizontal rule and has another one
///   further down would otherwise be swallowed whole. Every top-level line
///   between YAML fences therefore has to look like YAML (see
///   `looksLikeYAMLHeaderLine`). `+++` has no meaning in CommonMark at all,
///   so TOML is accepted on its fences alone — which also avoids rejecting
///   multi-line TOML arrays, whose closing `]` and `[table]` headers sit at
///   column 0 and look nothing like YAML.
///
/// False negatives are cheap and false positives are not: a rejected
/// candidate renders exactly as it would with no frontmatter support at
/// all, which is also what GitHub does with a header it cannot parse.
func frontmatterSpan(in raw: String) -> FrontmatterSpan? {
    guard let opening = physicalLine(of: raw, at: raw.startIndex) else { return nil }

    let closers: Set<String>
    let guardContent: Bool
    switch String(opening.text) {
    case "---":
        closers = ["---", "..."]
        guardContent = true
    case "+++":
        closers = ["+++"]
        guardContent = false
    default:
        return nil
    }

    var cursor = opening.nextStart
    while let line = physicalLine(of: raw, at: cursor) {
        if closers.contains(String(line.text)) {
            return FrontmatterSpan(
                // The trim mirrors the block splitter's per-block trim, so a
                // CRLF file's closing fence loses its `\r` here exactly as it
                // would there.
                block: String(raw[raw.startIndex..<line.textEnd])
                    .trimmingCharacters(in: .newlines),
                bodyStart: line.nextStart
            )
        }
        if guardContent && !looksLikeYAMLHeaderLine(line.text) { return nil }
        cursor = line.nextStart
    }
    return nil
}

/// True if `line` is shaped like a line of a YAML mapping. Applied only to
/// lines that start at column 0: an indented line is a continuation of the
/// one above it — a folded scalar's text, a nested mapping, a sequence item
/// — and can hold anything at all.
private func looksLikeYAMLHeaderLine(_ line: Substring) -> Bool {
    guard let first = line.first else { return true }
    switch first {
    case " ", "\t":  // blank-but-not-empty, or a continuation
        return true
    case "#":        // comment
        return true
    default:
        break
    }
    if isSequenceItem(line) { return true }
    return mappingColonIndex(line) != nil
}

/// The `:` separating a YAML mapping key from its value: the first colon
/// followed by a space, a tab, or the end of the line. That is YAML's own
/// rule, and it is what makes `type:` and `summary: >-` mappings while
/// `http://example.com` and a prose sentence are not. Nil when the line is
/// not a mapping entry at all.
private func mappingColonIndex(_ line: Substring) -> Substring.Index? {
    var searchFrom = line.startIndex
    while let colon = line[searchFrom...].firstIndex(of: ":") {
        let after = line.index(after: colon)
        if after == line.endIndex { return colon }
        if line[after] == " " || line[after] == "\t" { return colon }
        searchFrom = after
    }
    return nil
}

/// True if `line` is a YAML sequence entry: `- item`, or a bare `-`.
private func isSequenceItem(_ line: Substring) -> Bool {
    line == "-" || line.hasPrefix("- ")
}

/// One physical line of `raw`, plus the two indices the scanner needs:
/// where the text ends (at the line break) and where the next line begins.
private struct PhysicalLine {
    /// Line content with any trailing `\r` dropped, so the exact-match
    /// fence tests and the shape test never have to think about CRLF.
    let text: Substring
    let textEnd: String.Index
    let nextStart: String.Index
}

/// Read the line starting at `start`, or nil at end of input.
///
/// The scan runs over the unicode scalar view: in a CRLF file `\r\n` is a
/// single `Character`, so searching the `Character` view for `\n` finds no
/// line breaks whatsoever. Slicing the string at a scalar index between the
/// `\r` and the `\n` is well defined and leaves the `\r` on the line, which
/// is also where `components(separatedBy: "\n")` leaves it.
private func physicalLine(of raw: String, at start: String.Index) -> PhysicalLine? {
    guard start < raw.endIndex else { return nil }
    let scalars = raw.unicodeScalars
    var end = start
    while end < raw.endIndex, scalars[end] != "\n" {
        end = scalars.index(after: end)
    }
    var text = raw[start..<end]
    if text.last == "\r" { text = text.dropLast() }
    return PhysicalLine(
        text: text,
        textEnd: end,
        nextStart: end < raw.endIndex ? scalars.index(after: end) : raw.endIndex
    )
}

// MARK: - Rows

/// One line of a metadata header, reduced to what a properties table shows.
struct FrontmatterRow: Equatable {
    /// Nil when the line could not be read as an entry — the value then
    /// stands on its own across the full width of the table.
    let key: String?
    let value: String
}

/// Reduce a header block — fences included, exactly as `frontmatterSpan`
/// returns it — to display rows.
///
/// This is emphatically *not* a YAML or TOML parser: it recognizes enough
/// structure to lay metadata out as key/value pairs and treats anything it
/// does not understand as a keyless row rather than failing. Nothing here
/// can reject a document; by the time it runs, the block is already known
/// to be a header.
///
/// The shapes it does understand:
///
/// - `key: value` / `key = value`, with one pair of matching surrounding
///   quotes stripped from key and single-line value, the way any consumer
///   of the metadata would see them after parsing.
/// - Continuation groups — the indented lines under a key. A block scalar
///   (`>`, `|`, and their chomping variants) folds or keeps line breaks as
///   YAML would; a key with an empty value keeps its nested mapping or
///   sequence verbatim. Groups are dedented by their own smallest indent,
///   so nesting stays visible without carrying the source's columns.
/// - TOML `[section]` headers, which become a key with no value, and
///   multi-line arrays, which are held together by bracket depth because
///   their closing `]` conventionally sits back at column 0.
func frontmatterRows(_ block: String) -> [FrontmatterRow] {
    var lines = rawLines(of: block)
    guard let opening = lines.first else { return [] }
    let isTOML = opening == "+++"

    if opening == "---" || opening == "+++" { lines.removeFirst() }
    if let closing = lines.last, closing == "---" || closing == "..." || closing == "+++" {
        lines.removeLast()
    }

    var rows: [FrontmatterRow] = []
    var cursor = 0
    while cursor < lines.count {
        let line = lines[cursor]
        cursor += 1
        if isBlank(line) || line.first == "#" { continue }

        if isTOML {
            rows.append(tomlRow(line, in: lines, cursor: &cursor))
        } else if isSequenceItem(line) {
            rows.append(FrontmatterRow(key: nil, value: String(line)))
        } else if let colon = mappingColonIndex(line) {
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            let scalar = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let group = continuationGroup(in: lines, cursor: &cursor)
            rows.append(FrontmatterRow(
                key: unquoted(key),
                value: yamlValue(scalar, group: group)
            ))
        } else {
            rows.append(FrontmatterRow(
                key: nil,
                value: line.trimmingCharacters(in: .whitespaces)
            ))
        }
    }
    return rows
}

/// The lines belonging to the entry that ends at `cursor`: everything
/// indented or blank up to the next line at column 0, trailing blanks
/// dropped, dedented by the group's own smallest indent.
private func continuationGroup(in lines: [Substring], cursor: inout Int) -> [String] {
    var group: [Substring] = []
    while cursor < lines.count {
        let line = lines[cursor]
        guard isBlank(line) || line.first == " " || line.first == "\t" else { break }
        group.append(line)
        cursor += 1
    }
    while let last = group.last, isBlank(last) { group.removeLast() }
    return dedented(group)
}

/// A YAML value assembled from the scalar on the key's own line and the
/// group of lines under it.
private func yamlValue(_ scalar: String, group: [String]) -> String {
    guard !group.isEmpty else { return unquoted(scalar) }
    switch scalar {
    case ">", ">-", ">+":
        return folded(group)
    case "|", "|-", "|+":
        return group.joined(separator: "\n")
    case "":
        // A nested mapping or sequence: the group is the whole value.
        return group.joined(separator: "\n")
    default:
        return ([scalar] + group).joined(separator: "\n")
    }
}

/// Fold a block scalar the way YAML's `>` does: line breaks between
/// non-empty lines become spaces, and a blank line is a real break.
private func folded(_ group: [String]) -> String {
    var out = ""
    var breaks = 0
    for line in group {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            breaks += 1
            continue
        }
        if out.isEmpty {
            out = line
        } else {
            out += breaks > 0 ? String(repeating: "\n", count: breaks) : " "
            out += line
        }
        breaks = 0
    }
    return out
}

/// One TOML line, plus any lines an unclosed array pulls in after it.
private func tomlRow(_ line: Substring, in lines: [Substring], cursor: inout Int) -> FrontmatterRow {
    let text = line.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("[") {
        return FrontmatterRow(key: text, value: "")
    }
    guard let equals = text.firstIndex(of: "=") else {
        return FrontmatterRow(key: nil, value: text)
    }
    let key = text[text.startIndex..<equals].trimmingCharacters(in: .whitespaces)
    let value = text[text.index(after: equals)...].trimmingCharacters(in: .whitespaces)

    // An array written across several lines closes with a `]` at column 0,
    // so indentation cannot delimit it — bracket depth has to.
    var depth = bracketDepth(value)
    guard depth > 0 else { return FrontmatterRow(key: key, value: unquoted(value)) }
    var group: [Substring] = []
    while cursor < lines.count, depth > 0 {
        let next = lines[cursor]
        cursor += 1
        group.append(next)
        depth += bracketDepth(next)
    }
    return FrontmatterRow(key: key, value: ([value] + dedented(group)).joined(separator: "\n"))
}

/// Net `[` minus `]`, ignoring brackets inside quoted strings and anything
/// after a `#` comment, so a value like `name = "Tower [12]"` stays on one
/// line.
private func bracketDepth(_ text: some StringProtocol) -> Int {
    var depth = 0
    var openQuote: Character? = nil
    for c in text {
        if let quote = openQuote {
            if c == quote { openQuote = nil }
            continue
        }
        switch c {
        case "\"", "'": openQuote = c
        case "[": depth += 1
        case "]": depth -= 1
        case "#": return depth
        default: break
        }
    }
    return depth
}

/// Drop the smallest leading indent shared by the group's non-blank lines.
private func dedented(_ group: [Substring]) -> [String] {
    let indent = group
        .filter { !isBlank($0) }
        .map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }
        .min() ?? 0
    return group.map { isBlank($0) ? "" : String($0.dropFirst(indent)) }
}

/// Strip one matching pair of surrounding quotes — a display nicety that
/// shows the string a parser would hand back, not its source spelling.
private func unquoted(_ text: String) -> String {
    guard text.count >= 2, let first = text.first, text.last == first,
          first == "\"" || first == "'" else { return text }
    return String(text.dropFirst().dropLast())
}

private func isBlank(_ line: Substring) -> Bool {
    line.allSatisfy { $0 == " " || $0 == "\t" }
}

/// Every physical line of `text`, CRLF-safe (see `physicalLine`).
private func rawLines(of text: String) -> [Substring] {
    var out: [Substring] = []
    var cursor = text.startIndex
    while let line = physicalLine(of: text, at: cursor) {
        out.append(line.text)
        cursor = line.nextStart
    }
    return out
}
