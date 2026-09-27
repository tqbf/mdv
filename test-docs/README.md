# mdv Test Docs

Sample documents for exercising mdv's rendering paths and themes.
Open this directory with `mdv test-docs/` (or `make run` and drag the
folder onto the window) — mdv loads README first and seeds the
history sidebar with the rest.

## What's here

- [syntax.md](syntax.md) — every CommonMark + GFM construct mdv
  knows how to render: paragraphs, emphasis, links, lists, tables,
  task lists, blockquotes, footnotes, horizontal rules, escaping
- [code.md](code.md) — fenced code blocks for **every bundled
  tree-sitter grammar** (bash, c, go, javascript, python, ruby,
  rust, toml, yaml). Use this to verify the syntax highlighter and
  the per-theme code palette.
- [diff.md](diff.md) — `diff` and `patch` fenced blocks: a two-file
  git diff, a header-less snippet, and a removed line that looks like
  a `---` file header. Verifies diff tinting per theme.
- [tables.md](tables.md) — alignment, long cells, narrow cells, the
  full GFM table corner cases
- [images.md](images.md) — relative paths, absolute paths, missing
  references, and a couple of inline data: URIs. Verifies the
  `LocalImageProvider`.
- [raw-html-images.md](raw-html-images.md) — raw `<img>` tags: a sized
  header image, width/height/neither, single-quoted and bare attribute
  values, one inline in a sentence, a missing file, a remote source, and
  the fences and inline code that must keep their HTML literal. Verifies
  `RawHTMLImages` and the sizing shared by the screen and print.
- [links.md](links.md) — every link shape: md-to-md (navigates
  in-app), URL (opens in browser), mailto, fragment, broken refs.
  Verifies the `OpenURLAction` interception.
- [prose.md](prose.md) — long-form text designed for the reading
  themes (Sevilla, Solarized Light). Try toggling between Sevilla
  and Charcoal to see typography hierarchies.
- [toc-stress.md](toc-stress.md) — many headings at every level so
  you can exercise the TOC pane, the spyglass-collapse search, and
  the "On this page" affordances.
- [math.md](math.md) — `$…$` and `$$…$$` LaTeX: inline, display,
  environments (cases/matrices/aligned), math inside lists, quotes,
  tables and headings, plus the dollar signs that must stay literal
  (prices, `\$`, code). Verifies `MathMarkdown` + SwiftMath.
- [thematic-break.md](thematic-break.md) — every CommonMark
  thematic-break variant (`---`, `----`, `* * *`, `_ _ _`, `- - -`,
  setext H2) plus inline dash sequences that must *not* become rules.
  Useful for verifying thematic-break rendering with View → Smart
  Typography on and off.
- [gantt.md](gantt.md) — a Mermaid `gantt` diagram. Rendered via
  WKWebView + bundled mermaid.js (BeautifulMermaid does not support
  this type). Use it to verify fallback rendering, light/dark theme
  switching, and the source-view toggle.
- [mermaid-web-fallback.md](mermaid-web-fallback.md) — one of every
  other diagram type that goes through the WKWebView fallback (pie,
  timeline, mindmap, journey, quadrant chart, requirement diagram)
  plus a flowchart with a `%%{init}%%` directive and a `%%` comment
  before the keyword to verify the native dispatcher still finds
  it. If anything in here renders as the "could not be rendered"
  plate, the type-detector is at fault.
- [frontmatter.md](frontmatter.md) — a YAML metadata header at the top
  of a file, with the folded scalars, sequences, and nested mappings
  real headers use. Three companions cover the rest of the family:
  [frontmatter-ellipsis-close.md](frontmatter-ellipsis-close.md) (`...`
  closer, blank line inside the header),
  [frontmatter-toml.md](frontmatter-toml.md) (`+++` fences, multi-line
  array), and [frontmatter-negative.md](frontmatter-negative.md), which
  opens with a genuine thematic break and must keep rendering as
  ordinary prose.

## Quick checklist

1. **Themes** — flip through the palette menu in the toolbar. Sidebar,
   inspector, drag handles, title bar, and traffic-light buttons should
   all swap with the document body.
2. **Find** — ⌘F. Matches inside paragraphs/headings/lists should be
   highlighted character-by-character (yellow). The current match's
   block is brighter.
3. **TOC** — ⌥⌘0. Search the headings via the spyglass.
4. **Live reload** — open one of these files in your editor of choice
   (File → Edit → Choose Editor…), save it, watch the viewer update.
5. **Bookmarks** — ⌘D in any block adds a bookmark. ⌘1–⌘9 jumps.
6. **Images** — see [images.md](images.md). The relative one should
   render; the broken reference should show a "image not found"
   placeholder. Raw `<img>` tags are [raw-html-images.md](raw-html-images.md).
7. **Print** — ⌘P (or the panel's PDF dropdown) on
   [math.md](math.md), [gantt.md](gantt.md) and
   [raw-html-images.md](raw-html-images.md): formulas and diagrams should
   come out as vector glyphs, not rasters, and the printed page should lay
   out like the window.

## Notes

These docs are intentionally a bit silly in places — better to have
something fun on screen than yet another lorem ipsum dump.
