---
title: "Tide Table, Revision 9"
kind: field-report

# The blank line above, and this comment, are both inside the header.
observers:
  - Dot Marlin
  - Ash Peake
depth_m: 61
...

# Frontmatter closed with `...` — rendering test

YAML lets a document end with `...` instead of a second `---`, and
Pandoc-style headers use it often enough to be worth handling. The block
above this text is closed that way, and mdv should treat it exactly like
a `---`-closed header.

The header also contains a blank line and a `#` comment. Both are legal
inside YAML, and neither one splits the header: it is a single metadata
block, not three fragments of one.

Below the fence, normal document rules apply again — this paragraph is
prose, and the heading above it is in the TOC.
