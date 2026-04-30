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
- [tables.md](tables.md) — alignment, long cells, narrow cells, the
  full GFM table corner cases
- [images.md](images.md) — relative paths, absolute paths, missing
  references, and a couple of inline data: URIs. Verifies the
  `LocalImageProvider`.
- [links.md](links.md) — every link shape: md-to-md (navigates
  in-app), URL (opens in browser), mailto, fragment, broken refs.
  Verifies the `OpenURLAction` interception.
- [prose.md](prose.md) — long-form text designed for the reading
  themes (Sevilla, Solarized Light). Try toggling between Sevilla
  and Charcoal to see typography hierarchies.
- [toc-stress.md](toc-stress.md) — many headings at every level so
  you can exercise the TOC pane, the spyglass-collapse search, and
  the "On this page" affordances.

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
   placeholder.

## Notes

These docs are intentionally a bit silly in places — better to have
something fun on screen than yet another lorem ipsum dump.
