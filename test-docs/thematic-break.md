# Thematic Break — rendering test

Three hyphens (standard):

---

Four hyphens:

----

Five hyphens:

-----

Ten hyphens:

----------

Asterisks:

***

Underscores:

___

With spaces between:

- - -

* * *

_ _ _

---

## Setext H2 heading

The following heading uses a setext-style underline of hyphens:

This is a second-level heading
----

This is a regular paragraph after it.

---

## Smart typography near rules

This paragraph contains an em-dash via `---`: word --- word.

And here a range via `--`: 2020--2025.

These transformations should work as usual; only horizontal rules should render as lines, not text.

---

## Edge cases

Hyphens inside text (must not become a rule):

A line with hyphens in the middle: foo --- bar and foo ---- bar.

CLI flags must not be touched: `--verbose` and `--output`.
