---

TODO: reprint the stairwell notice before the inspection.
This second line is ordinary prose, and it is the reason the block above
is not a metadata header — a colon-shaped first line alone proves
nothing.

---

# Not frontmatter — rendering test

This file must render exactly like a normal document: the `---` on line 1
is a horizontal rule, the `---` after the paragraph is a second one, and
nothing here gets metadata treatment.

It is the case a lazier detector gets wrong. `---` at the top of a file
is a perfectly legal thematic break, and a paragraph that happens to open
with `TODO:` looks key-shaped if you only read one line. Checking every
line of the candidate is what keeps this document intact.

Compare with [frontmatter.md](frontmatter.md), where the same fences do
mean metadata.
