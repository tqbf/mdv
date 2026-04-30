# CODEVIEW — making code blocks awesome

The viewer renders prose well. Code blocks are the obvious laggard: they're a monospaced grey-fill rectangle and nothing else. Half the markdown people read in 2026 is technical; this is the highest-leverage refinement still on the table.

This doc is the full menu — everything we could plausibly do — followed by a recommended path through it. Source of truth is `mdv/ThemeManager.swift` (`.codeBlock` builder, around line 233) and `mdv/ContentView.swift` (per-block render, around line 706).

## Current state

```swift
.codeBlock { configuration in
    ScrollView(.horizontal) {
        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .relativeLineSpacing(.em(0.225))
            .markdownTextStyle {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.85))
            }
            .padding(16)
    }
    .background(sbg)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .markdownMargin(top: 0, bottom: 16)
}
```

What we have:
- Per-theme `secondaryBackground` fill, 6pt corner radius, monospaced font at 0.85em.
- Horizontal scroll (long lines no longer clip — `PROGRESS.md` line 156's "open" item is stale, worth striking when we land Phase 1).
- No syntax highlighting. No language label. No copy button. No line numbers. No wrap toggle. No diff tinting. No collapse for tall blocks. No language sniffing.
- Inline code rendered as a pill via `.code { … }` (separate builder).

What's missing, ranked by user-felt impact:

1. **Syntax highlighting** — the single most-felt absence. Without it the app reads as a tech demo.
2. **Copy-to-clipboard** affordance — biggest ergonomic win. Currently you have to triple-click + cmd-C.
3. **Language label** — zero cost, big "this is finished" signal.
4. **Diff tinting** for ` ```diff ` blocks — surprise-and-delight.
5. **Line numbers** — useful for long blocks; opt-in.
6. **Collapse / "show N more lines"** — for blocks > some threshold.
7. **Per-block wrap toggle** — opt-in for the small fraction of blocks where horizontal scroll annoys.
8. **Per-line copy / strip-shell-prompt** — power-user nicety.

## Phase 1 — Syntax highlighting (foundation)

Without highlighting, the rest of the polish is rearranging deck chairs. Do this first; the toolbar + line numbers + diff tints all hang off the same render path.

### Engine: SwiftTreeSitter + vendored grammars

[SwiftTreeSitter](https://github.com/ChimeHQ/SwiftTreeSitter) is a Swift wrapper over the C tree-sitter library. SPM-installable, no JS, no Rust toolchain, no extra build phases. Used by Chime, Edit (Mac), and a number of other native-feeling macOS editors. The point of mdv is native; this matches.

Why not the alternatives:

- **Highlightr** uses highlight.js via `JSContext`. Adds ~3 MB binary, JS bridge, and undermines the "native, no Electron-isms" thesis. Out.
- **`tree-sitter-highlight`** (Rust crate) wraps the same C library SwiftTreeSitter wraps. Adds Cargo + `lipo` to the build for nothing we actually need. Out.
- **Splash** (sundell) is Swift-first; Go and Rust are not its audience. Out.

SwiftTreeSitter buys us:

- Pure Swift Package Manager integration; `xcodebuild` stays one command.
- Per-language `Parser` / `Tree` / `Query` / `QueryCursor` types. Parse the snippet, run a `highlights.scm` query against the tree, walk the captures, build an `AttributedString`. ~50 lines of Swift to glue it together.
- Tree-sitter is incremental, so re-highlighting after find or theme changes is cheap.

### Languages and grammars

| Language | Grammar repo | Scanner |
| --- | --- | --- |
| C | tree-sitter/tree-sitter-c | `parser.c` |
| Go | tree-sitter/tree-sitter-go | `parser.c` |
| Rust | tree-sitter/tree-sitter-rust | `parser.c` + `scanner.c` |
| Bash | tree-sitter/tree-sitter-bash | `parser.c` + `scanner.c` |
| JavaScript | tree-sitter/tree-sitter-javascript | `parser.c` + `scanner.c` |
| YAML | ikatyang/tree-sitter-yaml (or tree-sitter-grammars fork) | `parser.c` + `scanner.c` |
| TOML | tree-sitter-grammars/tree-sitter-toml | `parser.c` + `scanner.c` |
| Python | tree-sitter/tree-sitter-python | `parser.c` + `scanner.c` |
| Ruby | tree-sitter/tree-sitter-ruby | `parser.c` + `scanner.c` |
| diff | (see Phase 5 — prefix-based row tinting beats syntax highlighting here) |

Language alias map at the resolver: `js` → javascript, `sh`/`zsh` → bash, `py` → python, `rb` → ruby, `yml` → yaml. Unknown / missing fence info → render as plain monospace, no error, no highlight (Phase 8 covers content-sniffing as a follow-up).

Disk footprint estimate: ~300–500 KB per grammar compiled, ~3–4 MB total bundled. Comparable to Highlightr; native.

### Vendoring strategy

Each grammar lives at `mdv/Grammars/<lang>/` with `parser.c`, optional `scanner.c`, and the upstream `queries/highlights.scm`. A `mdv/Grammars/README.md` records the upstream commit pinned for each grammar — bump manually when wanted, no Git submodules (the maintenance ergonomics on submodules with mixed-source SPM projects are ugly).

Wiring into `project.pbxproj`:

- One `PBXFileReference` per `parser.c` / `scanner.c` added to the existing Sources build phase. SwiftTreeSitter's docs show how to expose `tree_sitter_<lang>()` symbols to Swift via a small bridging header (`mdv/Grammars/Grammars-Bridging.h` listing each `extern const TSLanguage *tree_sitter_<lang>(void);`).
- `highlights.scm` files added to the Resources build phase, copied into the bundle, loaded via `Bundle.main.url(forResource:)` at runtime.

Adding a new grammar later: drop in the source files, add three pbxproj lines, add one line to the bridging header, register one entry in the language map. Minutes of work per addition.

### Theme palette plumbing

Each `MDVTheme` gains a `codePalette: CodePalette`:

```swift
struct CodePalette {
    let background: Color   // overrides secondaryBackground for code only
    let plain: Color        // identifiers, punctuation
    let keyword: Color
    let string: Color
    let number: Color
    let comment: Color
    let type: Color         // class / type names
    let function: Color     // function / method names
    let attribute: Color    // attributes / decorators / preprocessor
    let variable: Color     // local / parameter names (often == plain)
    let constant: Color     // constants, true/false/nil/None
    let operatorColor: Color
    let lineNumber: Color   // gutter
    let lineHighlight: Color // current-find-match line tint
    let diffAdd: Color
    let diffRemove: Color
    let diffAddBg: Color
    let diffRemoveBg: Color
}
```

Tree-sitter capture names map to palette slots. The standard captures (`@keyword`, `@string`, `@comment`, `@number`, `@type`, `@function`, `@variable`, `@constant`, `@operator`, `@attribute`, …) are consistent across well-maintained grammars; minor divergences (e.g., `@type.builtin` for Go's primitive types, `@function.macro` for Rust macros) collapse to their parent capture for our purposes. Resolution rule: walk the capture name from most-specific to least-specific, take the first slot that maps. Anything unmapped → `plain`.

Per-theme defaults (drafts — refine in implementation):

| Theme | Style |
| --- | --- |
| High Contrast | GitHub Light syntax (canonical: blue keywords, deep-green strings, grey comments) |
| Sevilla | muted earth-tone palette — desaturated indigo keywords, terracotta strings, warm grey comments. Reading-theme calm. |
| Charcoal | One Dark style: blue-purple keywords, soft green strings, mid-grey comments |
| Solarized Light / Dark | canonical Solarized accent assignments — the whole reason this palette exists |
| Phosphor | monochrome amber, brightness-only differentiation (CRT vibe; resist temptation to add green or red). |
| Twilight | pastel: cream keywords, mint strings, lilac types, warm-grey comments |

Rule: **don't blow the body-prose palette around.** Code highlighting should feel like part of the theme, not a separate stained-glass window. Saturation lower than what default editor themes ship with — we're displaying code mid-prose, not editing it.

### Caching

`CodeRenderer.shared` is an actor that maps `(language, code, themeID) → AttributedString`. Markdown blocks call `CodeRenderer.attributed(for:)` synchronously when cached, asynchronously otherwise — show plain monospace until tokenization completes, then crossfade. Memory cap ~5 MB; LRU eviction. `Parser` instances are reused per language (one per known language, lazily allocated), since constructing a parser is the only mildly expensive setup cost in tree-sitter.

### Tokenize-on-background

For a typical README, parse + query is well under 1 ms per block on Apple silicon. For long technical docs (a 2000-line Rust file pasted in), it's still milliseconds, but sum across 30 blocks on first paint and you can see it. Background-thread tokenization with a placeholder + crossfade keeps first paint snappy; cache hit on subsequent renders is near-free.

### MarkdownUI integration

MarkdownUI's `.codeBlock { configuration in … }` exposes the code text and the optional language. We replace `configuration.label` with our own renderer that:

1. Resolves the language via the alias map. Unknown / nil → render plain.
2. Calls `CodeRenderer.attributed(for: code, language:, palette: theme.codePalette)`. The renderer parses with the cached `Parser`, runs the `highlights.scm` `Query` via `QueryCursor`, walks captures into ranges on an `AttributedString`.
3. Renders into `Text(attributedString)` inside the existing horizontal-scroll container.
4. Falls back to plain monospaced render if any step fails — never crash on a malformed snippet.

### Theme palette plumbing

Each `MDVTheme` gains a `codePalette: CodePalette`:

```swift
struct CodePalette {
    let background: Color   // overrides secondaryBackground for code only
    let plain: Color        // identifiers, punctuation
    let keyword: Color
    let string: Color
    let number: Color
    let comment: Color
    let type: Color         // class / type names
    let function: Color     // function / method names
    let attribute: Color    // attributes / decorators / preprocessor
    let lineNumber: Color   // gutter
    let lineHighlight: Color // current-find-match line tint
    let diffAdd: Color
    let diffRemove: Color
    let diffAddBg: Color
    let diffRemoveBg: Color
}
```

Per-theme defaults (drafts — refine in implementation):

| Theme | Style |
| --- | --- |
| High Contrast | GitHub Light syntax (canonical: blue keywords, deep-green strings, grey comments) |
| Sevilla | muted earth-tone palette — desaturated indigo keywords, terracotta strings, warm grey comments. Reading-theme calm. |
| Charcoal | One Dark style: blue-purple keywords, soft green strings, mid-grey comments |
| Solarized Light / Dark | canonical Solarized accent assignments — the whole reason this palette exists |
| Phosphor | monochrome amber, brightness-only differentiation (CRT vibe; resist temptation to add green or red). |
| Twilight | pastel: cream keywords, mint strings, lilac types, warm-grey comments |

Rule: **don't blow the body-prose palette around.** Code highlighting should feel like part of the theme, not a separate stained-glass window. Saturation lower than the per-language defaults Highlightr ships with.

### Caching

`CodeRenderer.shared` is an actor (or a `DispatchQueue`-backed singleton) that maps `(language, code, themeID) → AttributedString`. Markdown blocks call `CodeRenderer.attributed(for:)` synchronously when cached, asynchronously otherwise — show the existing plain monospace render until tokenization completes, then swap in. Memory cap ~5MB; LRU eviction.

### Tokenize-on-background

For the typical README, tokenizing on the main thread is fine. For long technical docs (think: `swift-evolution` proposals), it stutters. Background-thread tokenization with a placeholder + crossfade is invisible for short blocks and respectful for long ones.

### MarkdownUI integration

MarkdownUI's `.codeBlock { configuration in … }` exposes `configuration.content` (the string) and `configuration.language` (optional). We replace `configuration.label` with our own renderer that:

1. Resolves the language (`configuration.language`, lowercased; map common aliases — `js`→`javascript`, `sh`/`zsh`→`bash`, `yml`→`yaml`).
2. Falls back to content-sniffing when language is missing (heuristics: starts with `{` and JSON-validates → json; first non-blank line starts with `#!/` → bash; etc.). Opt-in via theme flag; default off until tuned.
3. Calls `CodeRenderer.attributed(for: code, language:, palette: theme.codePalette)`.
4. Renders into `Text(attributedString)` inside the existing horizontal-scroll container.

## Phase 2 — Per-block toolbar — **shipped**

**Done.** `CodeBlockChrome` (in `mdv/CodeRenderer.swift`) wraps every fenced code block with a small chrome row (always-visible language label, hover-revealed Copy + Wrap toolbar) and a right-click context-menu mirror.

What's actually in:

- **Language label**: top-left, lowercase, dimmed (`tertiaryText` at 0.85 opacity), 10.5pt monospaced. Always visible. Strips fence-info trailing tokens (`python title=foo.py` → `python`).
- **Copy button**: `doc.on.doc` SF Symbol → `checkmark` morph for 1.2s on click, tinted with `theme.accent`. Reset is generation-counter-coalesced so rapid clicks don't bounce the icon.
- **Wrap toggle**: `text.append` → `text.alignleft`, persisted per-block-instance via `@State` (no UserDefaults yet — flipping wrap survives within the session but resets on file change/relaunch). Off → `ScrollView(.horizontal)`; On → `.fixedSize(horizontal: false, vertical: true)`.
- **Right-click menu** on the chrome row: Copy Code · Toggle Wrap · Copy Without Prompts (only when language ∈ {bash, sh, zsh, fish, shell, console} and ≥ 50% of non-empty lines start with `$ ` or `# `). The strip rule peels off both `$ ` and `# ` prefixes line-by-line.
- All seven themes still render their per-theme code palette through the new chrome — chrome itself is theme-aware (`tertiaryText` for the label, `secondaryText` for idle icons, `theme.accent` for active/copied state).

**Caveat — text-selection wins on the body**: SwiftUI's `.contextMenu` modifier on a parent view doesn't override the system text-selection menu inside `.textSelection(.enabled)` content. Right-clicking on the highlighted code itself shows the system menu (Look Up · Translate · Copy · …); right-clicking on the chrome row gets our custom menu. Acceptable for Phase 2 — toolbar buttons cover the same actions, and we don't want to disable text selection. Cleaner alternative if it bites later: an explicit "⋯" button in the toolbar that opens our menu programmatically, regardless of where the user is hovering.

**Deferred**: per-file persistence for the wrap toggle (today: `@State` only). Phase 3 will add line numbers and Phase 4 will add the collapse button — the toolbar already reserves space, so adding more icons is just `iconButton` calls inside the existing `HStack`.

## Phase 2 — Per-block toolbar (original spec, kept for reference)

A row of affordances pinned to the top-right of each code block, fading in on hover.

### Layout

```
┌─────────────────────────────────────────────────┐
│ swift                       [⤓] [⌥↩] [📋]       │
├─────────────────────────────────────────────────┤
│ 1  func greet(_ name: String) {                 │
│ 2      print("Hello, \(name)!")                 │
│ 3  }                                            │
└─────────────────────────────────────────────────┘
```

- **Language label** (left): lowercase, dimmed (`tertiaryText`), 11pt SF Mono. Always visible — not a hover affordance.
- **Toolbar** (right): fades in over 120ms on hover, 200ms delay-out. Buttons:
  - **Copy** (`doc.on.doc`) → clipboard, 1.2s confirmation morph to `checkmark`, accent tint.
  - **Wrap toggle** (`text.append`) → toggles soft-wrap for this block. Persists per file path (UserDefaults dictionary keyed by path → block-index list of wrapped indices). Clears on file change.
  - **Collapse** (`chevron.up.chevron.down`) → only present when block height > threshold (see Phase 4).

### Why hover

Persistent toolbars on every block become visual noise at scale (think: a 20-block tutorial). The language label stays visible for orientation; everything else hides until intent.

### Right-click menu (mouse-equivalent path)

Mirrors the toolbar so the affordance isn't lost when the user has the mouse on a tablet without hover, or invokes via keyboard:

- Copy Code
- Copy Without Shell Prompts (only shown when language ∈ {bash, sh, zsh, fish} and code contains `$ ` lines)
- Toggle Wrap
- Toggle Line Numbers
- Collapse / Expand
- Bookmark Here (existing `⌘D` already works at block granularity — confirm)

### Confirmation toast

For copy specifically: morph the icon, don't show a global toast. Toasts read as "the system did something" — a button confirming itself reads as "I did something." The button tint stays accent-colored for 1.2s, then fades back. Match the pattern in `ContentView.swift` find-bar success states.

## Phase 3 — Line numbers

### Default off, toggle on

Code blocks under ~6 lines look fussy with line numbers; long blocks benefit. Two ways to expose:

- **Per-block toggle** in the hover toolbar (see Phase 2). Persists per file path.
- **Global toggle** in the View menu (`Show Line Numbers ⌥⌘L`) overrides per-block state.

### Implementation

Render the gutter as a left-aligned `VStack` of `Text("\(n)")` inside a fixed-width container, separated from the code by 12pt and a 1px hairline (color: `theme.divider` at 0.5 opacity). Numbers use `theme.codePalette.lineNumber` at 0.85em monospaced.

The gutter is **outside** the horizontal `ScrollView`; only the code panel scrolls horizontally so line numbers stay put when the user scrolls right. (This rules out the "use AttributedString with line-number prefix" shortcut. Worth it.)

### Find integration

When the in-document find lands on a code block, additionally tint the matching line(s) with `theme.codePalette.lineHighlight`. Currently Find tints the whole block — fine for prose, sloppy for code. This requires per-line addressing inside the highlighted block, which the line-number gutter pass already gives us for free.

## Phase 4 — Collapsing tall blocks

> Show the first 12 lines of a 200-line block, with `… show 188 more lines` affordance below.

### Threshold

Default: collapse blocks > 24 lines to a 12-line preview. Tunable via `MDVTheme.codeBlockCollapseThreshold` (default 24, off when nil). Reading themes (Sevilla) might prefer no collapse — long code blocks aren't typical in the kind of writing Sevilla is for. Operational themes (Charcoal) want it on.

### Behavior

Collapsed state shows the first 12 lines (configurable), a fade-out gradient in the bottom 36pt, and a centered button: `Show 188 more lines  ⌥⌘.`. Click expands; chevron in the toolbar collapses. Expand state persists per file path (same dictionary as wrap-toggle state, namespaced).

Collapsed blocks still index for find. If a search match falls inside a collapsed region, expand the block automatically when the user navigates to it (mirror the existing TOC scroll behavior).

## Phase 5 — Diff tinting

` ```diff ` blocks get line-level treatment:

- Lines starting with `+` → `theme.codePalette.diffAddBg` row tint, `diffAdd` text.
- Lines starting with `-` → `diffRemoveBg` row tint, `diffRemove` text.
- `@@ … @@` hunk headers → italic, `secondaryText`.
- Context lines → plain monospaced.

The `+`/`-` characters themselves stay visible at the line head (don't strip — diffs are read for those characters). Tinting goes edge-to-edge inside the code panel so the rows feel like real diff hunks, not just colored text.

Implementation note: skip `tree-sitter-diff` here. The grammar exists, but the value of a rendered diff is the **row-level background tint**, which lives outside tree-sitter's text-coloring model. Prefix-based row classification (`+ `, `- `, `@@`) is 20 lines of Swift, exact, and gives us the row-tint hook the syntax-highlight path doesn't. If we ever want token-level coloring inside diff lines (e.g., highlighting the changed identifier within a `+` line), we can layer tree-sitter-diff on top later.

This is one of those features that disproportionately impresses — every PR description in the world is a diff block, and most viewers render them as plain monospace.

## Phase 6 — Selection ergonomics

### Triple-click → select line

Already mostly works via SwiftUI's `.textSelection(.enabled)` on the surrounding `LazyVStack`. Verify per-block selection doesn't accidentally bridge into the next block — it currently does, because the whole `LazyVStack` is one selectable region.

### Per-block selection isolation (stretch)

Putting `.textSelection(.enabled)` per-block would isolate selections but probably break cross-paragraph copy in prose. Verdict: leave selection as-is, ship the **Copy Code** button instead — that's what users actually want when they're trying to grab a single block.

### Strip-shell-prompts copy

For bash blocks containing `$ ` or `# ` line prefixes, offer **Copy Without Prompts** in the right-click menu. Heuristic: if ≥ 50% of non-empty lines start with `$ ` or `# ` followed by something, offer it. Strip on copy, leave the rendered block untouched.

Surprisingly common annoyance. Worth the 30 lines of code.

## Phase 7 — Inline code refinements

Out of scope of "code viewer" strictly, but the inline-code pill currently uses the same `secondaryBackground` as code blocks, so an inline ` `code` ` mention inside a code block disappears or worse looks like a button.

- Inline code: shift to a slightly different tint (`secondaryBackground.opacity(0.6)` over `background`, or a dedicated `inlineCodeBackground` field).
- Click-to-copy on inline code: probably not worth it. Adds hover/click semantics to text mid-paragraph, which fights selection. Skip.

## Phase 8 — Long tail

Things to consider, but not in the recommended path. Pulled out so they don't get lost.

- **Language sniffing** when the fence info is missing. Heuristics for json / xml / shell / sql / dockerfile. Default off; opt-in once we've seen the false-positive rate.
- **Whitespace markers** (per-block toggle: `⇥` for tabs, `·` for trailing spaces). Power-user; real audience is small.
- **Sticky language header** when scrolling inside a tall block. Handle in Phase 4 if collapse doesn't make this moot.
- **Embed renderers** (mermaid, dot, latex). Out of scope — viewer, not editor; adds heavy deps.
- **Block-level deep links** (`#code-N` URL fragments). Interesting for sharing, but no obvious surface for it in a desktop viewer.
- **Performance**: profile a 5000-line file with 100 code blocks. `LazyVStack` should already paginate; verify the cache works under that pressure.
- **Accessibility**: test minimum-size monospaced font readability under increased system text size. Capture-name palette contrast against each theme background.
- **Tab width**: configurable per-theme (default 4); only matters if we render tabs as visible spaces. Skip until a user complains.
- **Per-line bookmarks**: the existing per-block bookmark already covers code-block addressing. Per-line is over-scoped; one-block-one-anchor is the right granularity.

## Recommended path

Ship in this order, each independently shippable:

1. **Phase 1** (syntax highlighting + per-theme palette). Single biggest user-felt change. Lays the rendering pipeline that everything else uses. Estimate: 2–3 days incl. SwiftTreeSitter SPM hookup, vendoring 9 grammars + bridging header, capture→palette mapping, palette plumbing for all 7 themes, parser cache, and the async render path. The first grammar (probably C, simplest) takes most of day one; subsequent grammars are minutes each.
2. **Phase 2** (per-block toolbar + language label + copy). Cheap once Phase 1 is in. Estimate: half day.
3. **Phase 5** (diff tinting). Small, high-delight. Estimate: 2–3 hours.
4. **Phase 3** (line numbers, opt-in). Estimate: half day, mostly the find-line-highlight integration.
5. **Phase 4** (collapse). Estimate: half day.
6. **Phase 6** strip-shell-prompts. Estimate: 1 hour.
7. **Phase 7** inline-code disambiguation. Estimate: 30 min once we've stared at it post-Phase-1.
8. Phase 8 items as needed, never as planned.

After each phase: walk through all 7 themes on a representative file mix (a Go-heavy README, a Rust tutorial, a Bash one-pager, a YAML/TOML config doc, a diff-heavy CHANGELOG, a 1000-line code dump). Real-world test material lives under `~/codebase/` — pull a Go README, a Rust crate doc, a `kustomize.yaml`, etc. from there rather than synthesizing fixtures. Update `TYPOGRAPHY.md` with the per-theme code palette table when Phase 1 lands.

## Open questions

- **Grammar update cadence**: pin grammar commits in `mdv/Grammars/README.md` and bump on a "when something looks wrong" basis, or schedule a quarterly bump? Lean toward as-needed; tree-sitter grammars are fairly stable, and chasing upstream churn is a waste of attention.
- **YAML grammar choice**: `ikatyang/tree-sitter-yaml` is the long-standing community grammar; `tree-sitter-grammars/tree-sitter-yaml` is a maintained fork. Pick once, after a 30-min eval against a representative YAML mix (k8s manifests, GitHub Actions, ansible).
- **Per-language palette tuning**: do we hand-tune palette overrides per major language (e.g., give Rust's `unsafe` a redder keyword tone than Go's `func`)? Probably no — uniform palette per theme keeps the thing coherent across the 9 languages. Revisit only if user feedback demands it.
- **Wrap-toggle persistence scope**: per file path (resets when file changes name) vs. per file path *and* block index (specific block remembers). Per file path is simpler and probably what users expect.
- **Find highlighting at line-level vs. inline-token level**: line-level is what Phase 3 buys us. Per-token highlighting inside a syntax-highlighted code block requires merging two `AttributedString` range sets; doable but fiddly. Defer to Phase 3+ unless the line tint reads as too coarse.
- **Should the recommended path include a feature flag during rollout?** Probably no — all changes are user-facing improvements with no migration risk. Ship behind toolbar items where applicable; users discover by hovering.
