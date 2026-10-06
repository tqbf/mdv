---
title: "The Lighthouse Keeper's Inventory"
date: 2031-04-17
author: Wren Ashcombe
status: draft
summary: >-
  A folded scalar, which is why this value runs across several source
  lines and still counts as one string. Folded summaries are the usual
  reason a metadata header is taller than a couple of lines.
tags:
  - lighthouses
  - fog
  - inventory
metadata:
  edition: 3
  reviewed: true
  station:
    bearing: 214
    lamp_hours: 1096
---

# Frontmatter — rendering test

The block above this text is YAML frontmatter: a metadata header fenced
by `---`, starting at the very first byte of the file. mdv should present
it as metadata about the document, not as document prose.

It exercises the shapes a real header uses: a quoted string, a bare date,
a folded multi-line `summary: >-`, a sequence under `tags:`, and a nested
mapping under `metadata:` two levels deep.

If you would rather not look at it, View → Show Frontmatter hides the
header entirely and leaves the rest of the document exactly as it is.

## What the rest of the file should do

Everything below the closing fence is an ordinary document. This heading
belongs in the TOC (⌥⌘0), the paragraphs select and copy normally, and a
horizontal rule further down is just a horizontal rule:

---

Nothing about the header changes how the body renders.

## Related fixtures

- [frontmatter-ellipsis-close.md](frontmatter-ellipsis-close.md) — YAML
  ended with `...`, and a blank line inside the header
- [frontmatter-toml.md](frontmatter-toml.md) — `+++` fences
- [frontmatter-negative.md](frontmatter-negative.md) — a document that
  opens with a real thematic break and must be left alone
