+++
title = "Semaphore Timetable"
date = 2030-11-02
draft = false
weight = 40

[station]
name = "Relay Tower 12"
elevation_m = 340

[taxonomies]
tags = [
  "signals",
  "timetables",
  "relay-towers",
]
+++

# TOML frontmatter — rendering test

Static-site generators accept TOML headers fenced with `+++` as well as
YAML ones, so mdv recognizes both. The block above this text should be
presented as metadata.

Two details make this file worth keeping. The multi-line `tags` array
closes with a `]` at column 0, and the `[station]` and `[taxonomies]`
table headers also sit at column 0 — none of which looks remotely like a
YAML key. Unlike `---`, a `+++` line means nothing in CommonMark, so the
fences alone are enough to identify the header and no line inside it
needs to justify itself.

Everything after the closing fence is an ordinary document.
