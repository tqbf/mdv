# Markdown Syntax Tour

This document exercises every standard markdown construct mdv knows
how to render. If something here looks wrong, that's a bug in the
viewer — these are all bog-standard CommonMark or GFM extensions.

## Paragraphs and emphasis

A paragraph is just text separated by blank lines. *This is italic.*
**This is bold.** ***This is bold italic.*** ~~This is strikethrough~~
(GFM). `This is inline code` with `monospace` styling.

You can mix _underscore italic_ with **asterisk bold**, though the
canonical form is to pick one and stick with it. Lines without a
blank gap
just keep going as one paragraph.

To force a line break,
end a line with two spaces (above) — or use a `<br>` if you must.

## Links

Plain link to [GitHub](https://github.com).

Reference-style: [the Swift book][swift].

[swift]: https://docs.swift.org/swift-book/

Autolink: <https://example.com>.

Email autolink: <hello@example.com>.

Link with a title (hover to see it):
[hover me](https://example.com "Title attribute on the anchor").

## Headings

You've already seen `#` and `##`. Here are the rest:

### H3 — section heading

#### H4 — sub-section

##### H5

###### H6 — bottom of the hierarchy

## Lists

### Unordered

- Apples
- Pears
- Persimmons
  - Hachiya (eat soft)
  - Fuyu (eat firm)
- Quince

### Ordered

1. Wash the rice
2. Toast the rice in oil
3. Add stock and aromatics
4. Cover, simmer 18 minutes
5. Rest off heat 10 minutes

### Mixed and nested

1. **First**, gather:
   - Yeast (active or instant)
   - Flour, ideally bread flour
   - Salt
   - Water
2. **Then**, mix:
   - Until shaggy
   - Until smooth (10 minutes)
3. **Bulk ferment** until ~doubled
4. **Shape and proof**

### Task lists (GFM)

- [x] Replace Xcode project with SwiftPM
- [x] FSEvents-based live reload
- [x] Local image rendering
- [ ] Math rendering
- [ ] Mermaid diagrams
- [ ] Print to PDF

## Blockquotes

> Style is the answer to everything. A fresh way to approach a dull
> or dangerous thing. To do a dull thing with style is preferable to
> doing a dangerous thing without it.
>
> — Charles Bukowski (probably)

Nested:

> Outer quote.
>
> > Inner quote.
> >
> > > Three deep is plenty.
> >
> > Back out.
>
> Back to the outer.

## Code

Inline `let foo = bar()` and triple-backtick blocks live in
[code.md](code.md). A short example:

```swift
@main
struct mdvApp: App {
    var body: some Scene {
        Window("mdv", id: "main") { ContentView() }
    }
}
```

## Tables

Quick teaser; the real workout is in [tables.md](tables.md).

| Theme            | Light/Dark | Best for       |
|------------------|------------|----------------|
| High Contrast    | Light      | Default        |
| Sevilla          | Light      | Reading prose  |
| Charcoal         | Dark       | Technical docs |
| Solarized Light  | Light      | Code review    |
| Solarized Dark   | Dark       | Long sessions  |
| Phosphor         | Dark       | The CRT vibe   |
| Twilight         | Dark       | Late nights    |

## Horizontal rules

Below this paragraph is a rule.

---

The rule above is `---`. You can also use `***` or `___`.

***

## Footnotes (GFM)

This claim has a footnote.[^one] So does this one.[^two]

[^one]: Footnotes render as superscript markers that link to the
    bottom of the document.

[^two]: They're useful for citations or asides that would otherwise
    interrupt the flow of prose.

## Escaping

Backslash before a special character keeps it literal:

\*not italic\*, \# not a heading, \`not code\`, \[not a link\](url),
\> not a blockquote.

## HTML passthrough

Standard CommonMark allows raw HTML, though mdv (via MarkdownUI)
strips most of it. <kbd>⌘</kbd>+<kbd>F</kbd> is the keyboard shortcut
to open find — `<kbd>` may or may not survive depending on
configuration.

## Edge cases

- Lines with **only** whitespace: see what happens.
- A long line that should wrap nicely on narrow windows but stay on one line on wide ones, depending on the theme's `articleMaxWidth`. Compare Sevilla (620pt) with Charcoal (920pt) — same paragraph, very different reading rhythm.
- Unicode: 日本語、한국어、Ελληνικά, العربية (RTL!), 𝕞𝕒𝕥𝕙 𝕓𝕠𝕝𝕕, 🥑 emoji.
