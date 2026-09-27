# SPECIFICATION — mdv (Markdown viewer, native macOS GUI + CLI launcher, Swift/SwiftUI)

> - **Status:** v0.8 — implementation-grade uplift of the v0.7 as-built specification after the fifth review (`SPEC_REVIEW_REPORT.md`; F-001..F-093 applied). A plain §11 row is realised and verified; *not yet realised* marks specified work with no implementation; **open defect** marks known implemented behaviour that violates the normative row; *verification pending* marks a revised implemented path whose conformance has not yet been observed. Rows are never weakened to hide a defect.
> - **Language / stack:** Swift 5.9 (SwiftPM, no Xcode project) | SwiftUI + AppKit | MarkdownUI 2.4.1 (cmark-gfm) · SwiftTreeSitter 0.25.0 (manifest floor 0.8.0) + nine vendored tree-sitter grammars · beautiful-mermaid-swift 1.0.4 (ELK layout) · SwiftMath 1.7.3 (vendored, patched) · SQLite (FTS5) | surfaces: macOS app bundle, `bin/mdv` shell launcher, `make` targets
> - **Sources:** `README.md`; `mdv/Help.md` (user-facing behaviour); `NOTES.md` (library gaps and their work-arounds); `TYPOGRAPHY.md` (theme conventions); `plans/CODEVIEW.md` (code-block design); `Vendor/SwiftMath/README.md`; the implementation in `mdv/*.swift`, `bin/mdv`, `build.sh`, `Makefile`, `Package.swift`, `.github/workflows/build.yml`; git history through the v0.7 commit; `SPEC_REVIEW_REPORT.md` through F-093
> - **Scope of this document:** the observable behaviour of the mdv application and its launcher — file opening, rendering (Markdown, code, Mermaid, LaTeX), navigation, find and search, history, bookmarks, persistence, theming, packaging and release. It does **not** specify the internals of the third-party renderers beyond the contracts mdv relies on, nor the visual design values of individual themes (those live in `TYPOGRAPHY.md`).
> - **Normative language:** MUST/MUST NOT/SHALL/SHALL NOT = normative; SHOULD = strong recommendation; MAY = optional.
> - **Principle:** *Native and honest.* Every pixel is drawn by AppKit/SwiftUI/CoreText — no WebView, no JavaScript bridge — and when a renderer cannot handle an input, the user sees the source, never a blank.

---

## 0. Intent and purpose

mdv is a macOS application for *reading* Markdown. It renders a `.md` file the way a good document viewer renders a PDF: typographically deliberate, fast to open, with the navigation aids a long technical document needs (table of contents, in-document find, cross-file full-text search, bookmarks, back/forward history) and without any editing surface. It is meant to be the default handler for `.md` files on a developer's Mac, reachable from Finder, from the terminal (`mdv FILE`), and from other Markdown files via links.

The renderer is a pipeline of native components: cmark-gfm (via MarkdownUI) for Markdown, tree-sitter for code syntax highlighting, an ELK-based layout library for Mermaid diagrams, and a CoreText math typesetter for LaTeX. Each of those libraries has gaps relative to what real documents contain (Mermaid.js syntax, amssymb, `<br/>` in labels, …); mdv owns a **sanitising and repair layer** in front of each one so that documents written for GitHub or Mermaid.js render faithfully, and a **fallback rule** so that anything the layer cannot repair is shown as its source text with an explanation rather than dropped.

**Non-goals.** mdv does not edit Markdown (it hands off to an external editor); it does not render HTML blocks beyond what cmark-gfm passes through as text; it does not fetch remote images unless the user opts in; it does not sync anything off the machine; it is not sandboxed for the App Store (it reads arbitrary user files and installs a CLI symlink).

**Trust boundary.** Everything the application processes — file contents, link targets, image URLs, Mermaid and LaTeX source — is untrusted document content. The only runtime network activity is the user-enabled remote-image fetch governed by R-16 and C-16; the release pipeline (§10) is separate. The application never executes document content.

## 1. Actors and goals

| Actor | Goals |
| ----- | ----- |
| **Reader** (human, GUI) | Open Markdown files by any route, read them with good typography, move around them quickly, find text within and across files, keep places, and get back to files read before. |
| **Terminal user** (human, `bin/mdv`) | Open one or more files, a directory, or stdin from a shell in the running application; query the version; install the launcher once. |
| **Finder / LaunchServices** (`com.mdv.app` document-type registration) | Route double-clicks, drag-onto-icon, and `open -a` of `.md`/`.markdown`/`.mdown`/`net.daringfireball.markdown`/`public.plain-text` items into the application (C-01). |
| **External editor** (any macOS app the reader chooses) | Receive the current file on ⌘E; its saves are picked up by the live-reload watcher. |
| **Document author** (indirect) | Their GitHub-flavoured Markdown, Mermaid.js diagrams, and LaTeX math render as they would on GitHub / mermaid.live, or degrade visibly. |
| **Release engineer** (human, `make dist`, CI) | Produce a signed, notarised, stapled `.zip` from an exact `vX.Y.Z` tag; CI builds every push to `main` and publishes a rolling `latest` prerelease. |
| **Persistence store** (SQLite at `~/Library/Application Support/mdv/mdv.db`, `UserDefaults`) | Durably hold history, the full-text index, bookmarks, per-file scroll positions, and preferences across launches. |

## 2. Requirements (intent, high level)

Sources are cited as `[Help §…]`, `[README]`, `[NOTES]`, or a file path in `mdv/`.

### 2.1 Opening and loading

| ID | Statement |
| -- | --------- |
| **R-01** | The application MUST open a Markdown file from every one of: File → Open… (⌘O), Open in New Window… (⌘⇧O), a LaunchServices open event (Finder double-click, drag onto the icon, `open -a`), a file dropped onto the window, a Markdown link clicked inside a document (any local path, per R-19), a history-sidebar row, a search hit, a bookmark, the placeholder (R-28), and ⌘←/⌘→ (R-18). Routes are of two kinds: **adding routes** — ⌘O, ⌘⇧O, LaunchServices, drop, link, bookmark, placeholder, and the directory scan (R-02) — add the file's history row or move an existing one to the top (R-20) and index it (R-26); **selecting routes** — a history-sidebar row, a search hit whose file is already in history, ⌘←/⌘→, and the delete-current-row transition (§3.1) — display an entry the list already holds and MUST NOT reorder history or re-index. All routes MUST load the file into the **key window's** content view only; a second window (only ⌘⇧O creates one) MUST NOT react to a menu command or an open event addressed to another window (E-26). When one open event carries several URLs (`mdv A.md B.md`, a multi-file `open -a`), each MUST be added to history in the order received and the **last** MUST be displayed. `[Help §Opening files; mdv/mdvApp.swift application(_:open:); ContentView.loadFile (adding), List(selection:) / openHit / applySnapshot (selecting)]` |
| **R-02** | When the opened path is a **directory**, the application MUST consider the directory's non-hidden, readable files whose extension (case-insensitive) is `md`, `markdown`, or `mdown`, ordered by case-insensitive localized comparison of the filename; it MUST load `README.md` (case-insensitive match on the stem) if present, else the first file in that order, and MUST add every other such file to history as rows (not displayed, but indexed per R-26; primary first, the rest in that order) (R-20). `[Help §Opening files; ContentView.loadDirectory]` |
| **R-03** | Only the **first** item of a drop is considered (further items are ignored without error); it MUST be accepted only when its extension (case-insensitive) is one of `md`, `markdown`, `txt`, `mdown`, `mkd`; other drops MUST be ignored without error. `[ContentView.handleDrop]` |
| **R-04** | The file MUST be read and decoded as UTF-8 **before** any history change; a file that is not valid UTF-8, or that vanishes between the existence check and the read, is unreadable and the load MUST abort per E-03 — no history row, no selection change, no watcher re-arm. A file that decodes to zero bytes or only whitespace is readable: it MUST display an empty article with the file selected and watched, never the `EMPTY` panel (§3.1). The document MUST be split into **blocks** once per load (C-02) and every per-frame consumer (rendering, find, TOC, bookmarks) MUST read the cached split, never re-parse. `[ParsedDocument; commit 38df878; ContentView.loadFile/loadCurrentEntry]` |
| **R-05** | While a file is displayed, the application MUST watch it **by path** (not by open file descriptor or inode) and reload its content when the file changes on disk — a plain write, an atomic save that renames a temporary file over it, or a delete-and-recreate MUST all trigger a reload of the new content. Change events are delivered with a 50 ms latency and no deferral: the first event of a burst is delivered at once and later events within 50 ms are batched into at most one further delivery, so a burst yields at most **two** reloads and the content read last is the content displayed (K-06). A reload MUST keep the reader's scroll position (clamped to the new block count); any text selection is not preserved. A read that fails (file deleted, moved away, or not valid UTF-8 — a half-written save) MUST be ignored: the window keeps its content, shows no error, and keeps the watch armed for the path until a later event yields a readable file. A read that returns **zero bytes** while content is displayed MUST be treated as a truncate-then-write in progress: the page is kept and the file is re-read after 500 ms, and whatever that second read yields (including empty) is shown (E-21, D-18). `[FileWatcher (FSEvents on the parent directory); Help §Editor integration]` |
| **R-06** | On load, the application MUST restore the reader's last scroll position for that path (C-08) when the stored anchor still resolves (E-08); otherwise it MUST start at the top. It MUST persist the current position on window close, on quit, and before loading a different file into the window. `[ContentView.persistScrollPosition]` |

### 2.2 Rendering

| ID | Statement |
| -- | --------- |
| **R-07** | Markdown MUST be rendered as GitHub-flavoured Markdown (cmark-gfm: tables, task lists, strikethrough, autolinks, footnotes) using the active theme's typography (R-29). `[README; ThemeManager.markdownTheme]` |
| **R-08** | Fenced code blocks MUST be syntax-highlighted with tree-sitter for the languages in K-05 (with the alias map in C-05), and MUST render as plain monospaced text — never an error — for any other or missing language hint. The block MUST show a language label, a hover-revealed toolbar (wrap toggle, copy), and a context menu; blocks whose fence word is in the prompt-aware set of C-05 and whose non-empty lines are at least half `$ `/`# `-prompted MUST additionally offer *Copy Without Prompts*, whose output is the block with the leading `$ ` or `# ` removed from each prompted line and **every other line copied unchanged** (output lines are kept; line count is preserved). `[CodeRenderer; CodeBlockChrome.copyWithoutPrompts]` |
| **R-09** | A ` ```mermaid ` fence MUST render as a diagram image drawn natively (C-06). The block MUST offer: a style menu (Document, Light, Dark, Tokyo Night, Catppuccin — the choice persisted document-wide in `mdv.mermaid.style`), *Show Mermaid source* (toggles to a monospaced source view — no Mermaid grammar exists, so it is not syntax-coloured), *Export diagram as PNG*, copy source, and pinch-to-zoom between $0.5\times$ and $4\times$. `[Help §Diagrams and math; MermaidCodeBlockChrome]` |
| **R-10** | Before parsing, Mermaid source MUST be sanitised per C-06.1 so that the Mermaid.js constructs listed there render; after layout, the corrections in C-06.2 MUST be applied. A diagram whose source the library cannot parse (e.g. `timeline`, `gantt`, `pie`, `mindmap`) MUST render the fallback: the text "Mermaid diagram could not be rendered" and the source in monospace. `[NOTES §Mermaid]` |
| **R-11** | A diagram MUST be rasterised at the exact width from the §7.2 formula — its natural width or the available column width minus 36 pt, floored to whole points and bounded below by 1 pt — at the backing scale of the screen the window is on (as built: `NSScreen.main`, the screen of the key window). It MUST be re-rasterised when that width, committed zoom, or backing scale changes; the raster cache key includes all three. It MUST NOT be drawn wider than its natural width. `[NOTES §Resolution; MDVMermaidDiagramView]` |
| **R-12** | LaTeX math delimited by `$…$` (inline) and `$$…$$` (display) MUST be typeset natively with SwiftMath in every block type — paragraphs, headings, list items, blockquotes, table cells — following the delimiter rules in C-07. Display math on its own paragraph MUST be centred and MUST offer *Copy LaTeX* in its context menu. `[Help §Diagrams and math; MathRenderer]` |
| **R-13** | Math inside an ATX heading MUST be sized by that heading's em factor (C-09); elsewhere by the body size times the zoom factor (R-30). Math colour MUST be the theme's text colour. `[MathMarkdown.rewrite]` |
| **R-14** | LaTeX that SwiftMath rejects MUST render as its source (`$…$` delimiters included) in monospace; a display block MUST additionally show the parser's message. Before typesetting, the command rewrites and symbol registrations of C-07.2 MUST be applied. `[MathImageCache.typeset; MathSymbols]` |
| **R-15** | A node label in a Mermaid flowchart or state diagram that is exactly one `$$…$$` span MUST be typeset with SwiftMath and composited centred in the node at the same pixel weight as document math (I-009). Math mixed with text, and math in edge labels, MUST be rendered as the Unicode approximation of C-07.3. `[NOTES §LaTeX in labels]` |
| **R-16** | Images MUST resolve `data:` URIs inline and relative paths against the document's directory. `http(s)` images MUST NOT be fetched unless View → *Load Remote Images* is on; when on, the fetch MUST obey C-16, and turning the preference off MUST cancel in-flight remote-image requests. When off, a clickable "Remote image blocked" placeholder MUST be shown instead. A missing local image MUST show an "image not found" placeholder naming the file. Every local, data-URI, and remote image MUST obey K-14 and MUST NOT be scaled above its intrinsic size. `[LocalImageProvider; mdvApp View menu]` |
| **R-17** | When View → *Smart Typography* is on **and** the active theme allows it, prose blocks MUST be rendered with curly quotes, en/em dashes, and ellipses per C-10; fenced/inline code, GFM table blocks, thematic-break lines, link URLs, and `<…>` spans MUST be left verbatim. Math spans MUST be rewritten to image references *before* smartening so LaTeX is never altered. `[SmartTypography.swift; ContentView.blockView]` |

### 2.3 Navigation and copying

| ID | Statement |
| -- | --------- |
| **R-18** | The application MUST maintain per-window back/forward stacks whose entries are `(history entry, top block index)`. Loading a different file pushes the outgoing document's entry and clears the forward stack **except** when the load is initiated by a bookmark (R-27), the placeholder (R-28), or a cold-start file argument (R-40); those three routes MUST NOT push, whether their target is in the current file or another file. ⌘← pops a live snapshot, pushes the current view onto the forward stack, loads the file as a **selecting route** (R-01: history order and index untouched), and scrolls to the saved block; ⌘→ is the mirror. When a history row is removed (swipe-delete, cap eviction), every snapshot holding that entry MUST be dropped from both stacks or skipped when popped, so ⌘← never displays a document that has no history row. A same-document jump from a `#fragment` link (R-19) or TOC row (R-21) MUST push a snapshot and clear the forward stack; find stepping (R-24) MUST NOT push. Re-opening the current path pushes nothing. `[Help §Moving around; NavSnapshot, pushSameDocSnapshot]` |
| **R-19** | Clicking a link MUST navigate in-app when its path resolves to an existing local file whose extension is, case-insensitively, `md`, `markdown`, or `mdown`; otherwise it MUST hand the URL to the system opener — deliberately including `file:` paths and custom schemes, because a click is an explicit user action. Relative paths MUST be resolved by path arithmetic against the current document's directory. A fragment MUST be percent-decoded exactly once as UTF-8 before C-11 comparison; invalid percent encoding has no matching slug. A same-document `#fragment` MUST scroll to the first matching C-11 slug or do nothing when none matches (E-06). A local path plus fragment MUST load the target as an adding route, suppress R-06 scroll restoration, then scroll to its first matching slug; if no slug matches, the loaded file MUST remain at the top. Only C-02 single-line ATX `#`–`###` headings are targets (E-22, D-17). `[ContentView.handleLinkClick]` |
| **R-20** | The history sidebar MUST list every file opened by an adding route (R-01), most recently **added** first — a selecting route leaves the order unchanged — capped at 100 entries (the oldest is evicted), persisted across launches; a row MUST support swipe-to-delete. The sidebar MUST be collapsible (⌃⌘S, View menu, hover chevron) with the collapsed state persisted, and resizable by dragging its divider between 180 and 400 pt. `[HistoryManager; Help §Sidebars]` |
| **R-21** | The inspector MUST show a table of contents of the document's single-line ATX `#`, `##`, `###` headings (C-02), each row jumping to its block, with a search field that filters rows; and a collapsible bookmarks pane with a draggable height. The inspector's visibility and width (180–520 pt, dragged at its left edge) MUST persist. Heading text in the TOC MUST show math as Unicode (C-07.3), not as LaTeX source. `[Help §Sidebars; commit bcd2150]` |
| **R-22** | Prose blocks MUST support standard macOS text selection (drag to select; ⌘C copies the rendered text through the system pasteboard). A **TOC heading block** — a block listed in `tocHeadings` (C-02 rule 7: single-line ATX `#`–`###`); an h4–h6 or setext heading is prose for every rule in this row (E-22) — MUST NOT be text-selectable; the pointer over one MUST be the pointing hand; a click on one (a tap without drag — modifier keys are not distinguished) MUST copy that heading's section (C-12) as Markdown source to the pasteboard and flash the section for 0.6 s; a repeated click copies again and restarts the flash. There is no block-level selection model (it was removed in commit `c50817a`). `[commit c50817a; ContentView.copySection, BlockTextSelection]` |
| **R-23** | ⌘E MUST open the current file in the chosen external editor; File → Edit → *Choose Editor…* picks one and *Forget Editor* clears it; with no editor set, ⌘E MUST prompt to choose. `[Help §Editor integration]` |

### 2.4 Find, search, bookmarks

| ID | Statement |
| -- | --------- |
| **R-24** | ⌘F MUST open an in-document find bar. An empty query MUST produce no matches, show "No matches", and disable stepping; a non-empty query, including whitespace-only input, MUST be matched verbatim as a case-insensitive substring over each block's source (no trimming, no diacritic folding — unlike C-03). A reload (R-05) while the bar is open MUST recompute $m$ and return to the first occurrence. $m$ counts **occurrences** in document order, and the bar MUST show "$n$ of $m$" or "No matches". ⌘G / ⇧⌘G MUST step per occurrence, wrap at the ends, and scroll the occurrence's block into view; Esc MUST close. A matching block MUST be tinted as a whole when it is a code fence (` ``` `/`~~~`), a `$$` math fence (C-02 rule 3), a GFM table (first line contains `|`, second line consists only of `-`, `:`, `|`, space), or contains `![` anywhere. Every other matching block MUST be inline-highlighted: the block is re-rendered as inline text (leading `#`, `>`, and ordered-list markers stripped, `-`/`*`/`+` bullets shown as `•`, inline Markdown interpreted, math shown as `$…$` source) and every occurrence of the query in that text is marked, so an occurrence inside markup can be counted but unmarked, and vice versa (E-17). All occurrences in the current match's block share the stronger tint; the current occurrence is not otherwise distinguished from siblings in that block (D-21). When the sidebar was last focused, ⌘F MUST route to global search. `[Help §Find; ContentView find, shouldInlineHighlight, highlightedAttributedString]` |
| **R-25** | ⌘⇧F MUST focus a search field that queries the full-text index of every file in history (C-03): tokens are prefix-matched and ANDed; results (at most 80) MUST show the filename and a snippet with matched terms highlighted; choosing a result MUST open the file. `[Help §Find; Database.search]` |
| **R-26** | The application MUST index a file's content into the full-text index when it is added to history by an adding route (R-01: opened, or seeded as a directory sibling by R-02 — a selecting route does not re-index) and re-index history on launch, skipping any file whose modification time (whole seconds, K-06) is unchanged since its last indexing. Removing a file from history — swipe-delete **or eviction by the 100-entry cap** — MUST remove its row from the index (and its C-08 scroll position; bookmarks are kept), and launch MUST drop any index row whose path is not in history, so the search population is exactly the current history. (There is no *clear history* command; `HistoryManager.clear()` exists but is unreachable from the UI.)  `[Database.indexFile/removeFile; HistoryManager.add/remove]` |
| **R-27** | ⌘D MUST add a bookmark at the block under the pointer if one is hovered, else at the topmost block whose frame intersects the viewport; titled by the nearest TOC heading (C-02 rule 7) at or within the previous 40 blocks, using its display text (inline Markdown stripped per C-12, math per C-07.3); else the block's **first line** with inline Markdown stripped, truncated to 60 extended grapheme clusters (K-06); else `(line n)` with $n$ the 1-based block index when the stripped line is empty; `(empty)` only when the document has no blocks. The anchor is block index and fingerprint (C-08). Bookmarking the same block twice creates two rows. Bookmarks MUST persist in order; the first five MUST be bound to ⌘1…⌘5; rows MUST be reorderable by drag and removable. Opening a bookmark MUST load its file if needed and scroll to the resolved anchor without pushing a back-snapshot (R-18). `[Help §Bookmarks; BookmarksManager]` |
| **R-28** | ⌘⇧0 MUST set a transient in-memory placeholder — anchored by the R-27 rule (hovered block, else topmost visible block; index and fingerprint) and recording the file path — and ⌘0 MUST return to it, loading that file first (adding route, R-01) if another is displayed; ⌘0 with no placeholder, or whose file no longer exists (E-27), MUST beep (§5.1); the placeholder MUST NOT survive relaunch and does not push a back-snapshot (R-18). `[Help §Bookmarks; setPlaceholder, jumpToPlaceholder]` |

### 2.5 Appearance and preferences

| ID | Statement |
| -- | --------- |
| **R-29** | The reader MUST be able to choose one of the nine named themes or *System* from the toolbar; *System* MUST resolve to `high-contrast` in Light appearance and `twilight` in Dark and MUST switch live when macOS appearance changes. Each theme MUST restyle the article pane, code palette, and the diagram *Document* style; the choice MUST persist (`mdv_theme_id`). `[ThemeManager; TYPOGRAPHY.md]` |
| **R-30** | Let $s$ be the stored zoom factor and $d$ be $+0.10$ for ⌘= or $-0.10$ for ⌘-. Each step MUST set $s' = \operatorname{clamp}(\operatorname{roundHalfAway}(10s)/10 + d, 0.60, 2.50)$; `roundHalfAway` rounds a half-integer away from zero. View → Actual Size MUST set $s'=1.0$. The factor MUST persist (`mdv_font_scale`) and MUST scale body text, document math (R-13), inline code, and fenced code blocks (C-05: fence text at $0.85 \times$ base $\times s'$). The zoom HUD MUST appear after the change for 0.9 s and show $\lfloor 100s' + 0.5 \rfloor$ %. `[ThemeManager fontScale; CodeRenderer.render]` |
| **R-31** | ⌘? (Help → mdv Help) MUST open the bundled `Help.md`, copied (overwritten) to `~/Library/Application Support/mdv/Help.md` on **every** ⌘? so the copy matches the running build and has a stable path for history and bookmarks. Because each copy changes the file's mtime, the C-08 scroll position for Help is never restored across ⌘? invocations, and a ⌘? while Help is displayed triggers a reload (R-05). `[HelpManager]` |
| **R-32** | Every preference in C-04 MUST persist via `UserDefaults` under the listed key and MUST be honoured on the next launch. |

### 2.6 Launcher, packaging, diagnostics

| ID | Statement |
| -- | --------- |
| **R-33** | `bin/mdv` MUST implement the surface in §5.2: locate the app bundle per the documented search order, open files/directories by absolute path, read stdin into a temporary `.md` for `-`, print the bundle version for `--version`, and exit `1` with `mdv: no such file: <path>` on stderr for a missing argument. `[bin/mdv]` |
| **R-34** | `make` (default) MUST build a runnable `build/mdv.app` from a clean checkout with only the Swift toolchain, copying every resource the app needs (C-13); `make install` MUST place it in `/Applications`, register it with LaunchServices, and symlink the CLI. Every `make dist` invocation MUST refuse before building unless `HEAD` carries an exact `vX.Y.Z` tag; a command-line `VERSION` value MUST NOT bypass or replace that tag. `[Makefile; build.sh]` |
| **R-35** | The application MUST NOT print document content, file contents, or query strings to any log at any verbosity. The only diagnostics it emits are `NSLog` lines prefixed `[mdv]` — persistence-store failures (E-12, may name the file path), bundled-font registration failures, and an external-editor launch failure (R-23, whose error text may include the file path) — and the font-registration lines SwiftMath prints once per font on first use. |
| **R-36** | For every input admitted by K-14, the application MUST NOT terminate because of document content. A repair-layer or third-party parse/layout failure MUST degrade to the fallback of R-10/R-14/C-14, and every path that reaches a third-party parser MUST be preceded by the applicable validation and sanitisation. Inputs rejected by K-14 MUST follow E-28 without entering a third-party parser. `[NOTES §Mermaid: ELK layout asserts]` |
| **R-37** | The repository MUST carry an automated test suite runnable with `swift test` from a clean checkout, covering at least the pure contracts (C-02 block split, C-03 query construction, C-07.1 delimiters and C-07.3 plain text, C-08 fingerprint/resolve, C-10 smart typography, C-11 slugs, C-12 sections) and the Mermaid/LaTeX sanitisers (C-06.1, C-07.2), and CI MUST run it on every push to `main` and on every pull request. *Not yet built* — see D-01 and §9.0. |
| **R-38** | Fenced code blocks tagged `swift` and `sql` MUST be syntax-highlighted with tree-sitter like the languages of K-05: the `tree-sitter-swift` and `tree-sitter-sql` grammars (parser, scanner, and a `highlights.scm`) vendored under `mdv/Grammars/`, pinned in its README, compiled into `CGrammars`, and resolved from the fence hints in C-05 (`swift`; `sql`, `sqlite`, `postgresql`/`postgres`, `mysql`, `plsql`, `tsql`). Highlighting quality MUST match the existing languages: keywords, strings, comments, numbers, types, and function names each map to a palette capture. *Not yet built* — see D-15. |
| **R-39** | The repository MUST contain the render harness and corpus specified by C-17: `tools/render-harness/` MUST be a SwiftPM executable that links the application's pipeline code rather than copying it; `test-docs/mermaid/*.mmd` MUST contain one licence-cleared raw Mermaid diagram per file; and `test-docs/render-cases.json` MUST enumerate the deterministic render checks. The C-17 commands MUST make T-13, T-17, and T-19 reproducible from a clean checkout. *Not yet checked in* — see D-01. |
| **R-40** | On launch with no file argument, the main window MUST attempt exactly the first history entry (the most recently added path, R-20) and restore its scroll position (R-06). If that entry is unreadable, it MUST remain in history and the window MUST enter `EMPTY`; later rows MUST NOT be tried automatically. A cold-start file argument (LaunchServices, `bin/mdv FILE`) MUST pre-empt automatic history restoration, display that file, and MUST NOT create a back-stack snapshot for the unseen history head (R-18). The window MUST otherwise enter `EMPTY` only when history is empty. `[ContentView onAppear; application(_:open:)]` |
| **R-41** | Before reading, parsing, laying out, downloading, or decoding untrusted document content, the application MUST enforce the applicable K-14 ceiling. Content over a ceiling MUST follow E-28; admitted content MUST remain subject to R-36. Remote fetches MUST additionally obey C-16. *Not yet realised.* |

## 3. Behavior and state model

### 3.1 Document lifecycle

A window holds at most one **current document**. Its states and transitions:

| State | Meaning | Enters via | Leaves via |
| ----- | ------- | ---------- | ---------- |
| `EMPTY` | No file loaded; the drop target / Open… prompt is shown. History MAY be empty or may retain an unreadable initial head (R-40). | launch with empty history; failed load of the initial history head with no prior document (R-40, E-03); swipe-delete of the last history row while it is displayed (R-20) | any open route (R-01) → `LOADING` |
| `LOADING` | Outgoing document's scroll position persisted when one exists (R-06); file read and decoded (R-04), split into blocks (C-02); **adding route only**: history row added or moved to the top (R-20) and file indexed (R-26); **selecting route**: history and index untouched; scroll anchor looked up unless R-19 suppresses it. | adding or selecting route (R-01); launch with non-empty history (R-40, selecting); swipe-delete of the displayed row with other rows remaining (R-20, selecting) | success → `VIEWING` (an empty file is a success, R-04); unreadable file → the previous state (`VIEWING` of the prior document, or `EMPTY` if there was none), with no history or selection change (E-03). An unreadable initial history head therefore leaves the row in history and enters `EMPTY` (R-40). |
| `VIEWING` | Blocks rendered lazily; watcher armed on the path (R-05); find/TOC/bookmarks operate on the cached split. In-flight renders (diagram layout, math) are cancelled when the document changes. | `LOADING` | open of another file → `LOADING`; file changed on disk → `RELOADING`; file deleted → stays `VIEWING` (E-21); swipe-delete of the displayed history row → `LOADING` of the new first history entry (selecting route; position persisted; the deleted entry's snapshots dropped, R-18), or `EMPTY` when no rows remain (R-20); window close → `CLOSED` |
| `RELOADING` | New content replaces `rawMarkdown` in place; scroll position kept; text selection not preserved. Transient empty/undecodable reads are ignored (R-05, E-21). | watcher event, coalesced 50 ms | → `VIEWING` |
| `CLOSED` | Scroll position persisted (R-06); watcher cancelled. | window close, quit | terminal |

```mermaid
stateDiagram-v2
    [*] --> EMPTY : launch, empty history (R-40)
    [*] --> LOADING : launch, history head (R-40)
    EMPTY --> LOADING : adding or selecting route (R-01)
    LOADING --> VIEWING : read + decode + split OK (R-04), or unreadable with a prior document kept (E-03)
    LOADING --> EMPTY : unreadable, no prior document (E-03)
    VIEWING --> LOADING : adding route (row added or moved, indexed) or selecting route (row untouched), position persisted (R-06)
    VIEWING --> EMPTY : last history row deleted (R-20)
    VIEWING --> RELOADING : file changed on disk (R-05)
    VIEWING --> VIEWING : displayed path deleted or transient read rejected (E-21)
    RELOADING --> VIEWING : content swapped, position kept
    VIEWING --> CLOSED : window close / quit (R-06)
    CLOSED --> [*]
```

*Figure 3.1 — document lifecycle per R-01, R-04..R-06, R-20, R-40, E-03, E-21. The table is normative; the diagram is illustrative.*

### 3.2 Render pipeline for one block

Every visible block goes through the same path on each render (the split itself happens once per load, R-04):

```mermaid
flowchart TD
    B["block source (C-02)"] --> F{"fenced code?"}
    F -->|"mermaid"| M["MDVMermaidPipeline (C-06)"]
    F -->|"other / none"| TS["CodeRenderer: tree-sitter (C-05)"]
    F -->|"prose"| MR["MathMarkdown.rewrite (C-07.1)"]
    MR --> ST["smartenMarkdown (C-10), if enabled"]
    ST --> MU["MarkdownUI: cmark-gfm → SwiftUI"]
    MU --> IP["image providers: local / data: / remote-gated (R-16) / mdv-math (C-07)"]
    M --> IMG["NSImage at display width (R-11)"]
    TS --> AS["AttributedString, cached by (lang, theme, code)"]
```

*Figure 3.2 — per-block render path per R-07..R-17. Each edge corresponds to a §4 contract; the diagram is illustrative.*

Order matters in one place and is normative: **math rewriting precedes smart typography** (R-17), so that `--`, `...`, and quotes inside `$…$` are never curled or dashed.

### 3.3 Durable artifacts

| Artifact | Location | Written when | Read when |
| -------- | -------- | ------------ | --------- |
| History list | `UserDefaults["mdv_history"]` (JSON per C-15, $\leq 100$ entries) | every adding-route open (R-01), swipe-delete, cap eviction | launch |
| Full-text index | `mdv.db` tables `articles`, `articles_fts` (C-03) | every adding-route open (mtime-gated), launch re-index; rows removed on swipe-delete and eviction (R-26) | ⌘⇧F search |
| Bookmarks | `mdv.db` table `bookmarks` (C-08) | ⌘D, reorder, remove | launch, Bookmarks menu, inspector |
| Scroll positions | `mdv.db` table `scroll_positions` (C-08) | window close / quit / file switch (R-06); row removed with the history row (R-26) | file load |
| Preferences | `UserDefaults` keys in C-04 | on change | launch |
| Help file | `~/Library/Application Support/mdv/Help.md` | every ⌘? (overwritten from the bundle, R-31) | ⌘? |
| Render caches | in-memory only: code `AttributedString` (256 entries), math images (2048), Mermaid layouts (96) and rasters (192, $\leq 192$ MB) | render | render |

`mdv.db` MUST be opened with `SQLITE_OPEN_FULLMUTEX`, `journal_mode = WAL`, `synchronous = NORMAL` (I-006). Its `meta` table holds `schema_version` (currently `4`); `migrate()` MUST apply forward migrations by comparing it, each migration's statements and the version bump inside **one** transaction (`BEGIN IMMEDIATE … COMMIT`), so a crash mid-migration leaves the previous schema and version intact. A migration whose statement fails is rolled back and logged (E-12); the next launch retries it.

## 4. Interfaces / contracts

### C-01 Application bundle and document types

```
mdv.app/
  Contents/Info.plist        CFBundleIdentifier com.mdv.app, LSMinimumSystemVersion 13.0,
                             CFBundleShortVersionString 1.0.0
                             CFBundleDocumentTypes: extensions [md, markdown, mdown];
                             LSItemContentTypes [net.daringfireball.markdown, public.plain-text]
  Contents/MacOS/mdv         SwiftPM executable
  Contents/Resources/        AppIcon.icns · *.otf (Alegreya, Besley, OpenDyslexic) ·
                             *-highlights.scm (9) · mathFonts.bundle/ (Latin Modern Math + plist)
                             · mdv (CLI script, for "Install Command Line Tool…") · Help.md
Entitlements: app-sandbox = false; files.user-selected.read-only = true
```

### C-02 Document split: `ParsedDocument`

```swift
struct ParsedDocument {            // computed once per load (R-04); equality on `raw`
    let raw: String
    let blocks: [String]           // see rules
    let tocHeadings: [TOCHeading]  // level 1…3, single-line ATX only
}
struct TOCHeading { level: Int; text: String /*display*/; slugText: String /*for #fragment*/; blockIndex: Int }
```

Split rules (normative):

1. Input is split on `\n`. A **blank line** (only whitespace) ends the current block.
2. A line whose first non-space characters are ` ``` ` or `~~~` opens a **fence**; blank lines inside a fence do not split; the fence closes at the next line starting (after spaces) with the same three-character marker — *as built, the closing run is not required to be at least as long as the opener* (a deviation from CommonMark; see E-23). An unclosed fence runs to the end of the input.
3. A line whose first non-space characters are `$$`, with no second `$$` on the same line, opens a **math fence**; it closes at the next line *containing* `$$`, or at the end of the input.
4. Indented code blocks (four spaces) are **not** recognised by the splitter: a blank line inside one splits it into two blocks (E-23).
5. Leading/trailing newlines of a block are trimmed; empty blocks are dropped.
6. Line endings are normalised before splitting: `\r\n` and lone `\r` MUST be treated as `\n`, so a CRLF document yields the same blocks and TOC as its LF equivalent.
7. `tocHeadings` contains each block whose trimmed text starts with `# `, `## `, or `### ` and is not a fence, using its first line only. `text` is the line with inline Markdown stripped (C-12 rules) and math converted per C-07.3; `slugText` is the same without the math conversion.

### C-03 Full-text index

```sql
CREATE TABLE articles (id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, filename TEXT NOT NULL,
    content TEXT NOT NULL DEFAULT '', indexed_at INTEGER NOT NULL,
    file_mtime INTEGER NOT NULL DEFAULT 0, file_size INTEGER NOT NULL DEFAULT 0);
CREATE VIRTUAL TABLE articles_fts USING fts5(filename, content, path UNINDEXED,
    content='articles', content_rowid='id', tokenize='unicode61 remove_diacritics 2');
-- triggers keep articles_fts in step with INSERT/UPDATE/DELETE on articles
```

Query construction: split the input on whitespace; drop the characters `" ( ) : * ^` from each token; discard tokens that become empty; wrap every survivor as `"token"*`; join with spaces (FTS5 implicit AND). A query with no surviving tokens performs no search and yields no results. Results MUST use `ORDER BY rank ASC, path COLLATE NOCASE ASC, path ASC LIMIT 80`, with `snippet(articles_fts, 1, char(2), char(3), '…', 14)` — U+0002/U+0003 bracket matched terms and the UI renders them highlighted. The two path keys make equal-rank ordering deterministic, including the 80-row boundary.

### C-04 Preferences (`UserDefaults`)

| Key | Type | Default | Meaning |
| --- | ---- | ------- | ------- |
| `mdv_theme_id` | String | `high-contrast` | Theme id or `system` (R-29) |
| `mdv_font_scale` | Double | `1.0` | Zoom factor (R-30), clamped on read |
| `mdv_smart_typography` | Bool | `true` | View → Smart Typography (R-17) |
| `mdv_load_remote_images` | Bool | `false` | View → Load Remote Images (R-16) |
| `mdv_sidebar_collapsed` | Bool | `false` | History sidebar hidden (R-20) |
| `mdv_inspector_visible` | Bool | `false` | TOC/bookmarks inspector shown (R-21) |
| `mdv_inspector_width` | Double | `240` | Inspector width, clamped to $[180, 520]$ |
| `mdv_bookmarks_expanded` | Bool | `false` | Bookmarks pane open |
| `mdv_bookmarks_height` | Double | `240` | Bookmarks pane height, clamped at use (K-04) |
| `mdv_editor_app_path` | String | `""` | External editor bundle path (R-23) |
| `mdv_history` | Data (JSON) | `[]` | History entries (R-20, C-15) |
| `mdv.mermaid.style` | String | `document` | Diagram style (R-09) |

A stored value of the wrong type, outside its range, or not in its enumeration falls back to the default at use: an unknown `mdv_theme_id` resolves to `high-contrast` (the picker shows no selection until the reader picks one); `mdv_font_scale` is clamped on read and each step applies the R-30 round-half-away formula; widths and height are clamped per K-04; an unknown `mdv.mermaid.style` reads as `document`.

### C-05 Code highlighting: `CodeRenderer`

```swift
func render(code: String, languageHint: String?, theme: MDVTheme) -> AttributedString   // synchronous, never throws
```

- Language resolution: lower-case the info string, keep its first word; direct names `c go rust bash javascript yaml toml python ruby` (+ `swift sql` once R-38 lands); aliases `js jsx javascriptreact node → javascript`, `sh zsh shell → bash`, `py python3 → python`, `rb → ruby`, `yml → yaml`, `rs → rust`, `golang → go`, `h objective-c objc → c` (+ `sqlite postgresql postgres mysql plsql tsql → sql` per R-38); anything else → plain.
- Prompt-aware fence words (R-08 *Copy Without Prompts*): the **raw** first word of the info string, lower-cased, is one of `bash sh zsh fish shell console` — a separate test from language resolution (`fish` and `console` highlight as plain yet are prompt-aware; `shell-session` is not).
- Highlighting: parse with a fresh `Parser` per call, run the grammar's `highlights.scm`, colour each capture from the theme's `CodePalette` by capture-name components; `comment` captures are italic. If the query fails to compile, that language falls back to plain for the rest of the session. Fence text is set in the system monospace face at $0.85 \times$ `baseFontSize` $\times$ the zoom factor (R-30).
- Result cache: key `(language, theme id, zoom factor, hash(code))`, at most 256 entries (flushed whole when full).

### C-06 Mermaid pipeline: `MDVMermaidPipeline`

```swift
static func prepare(source: String, theme: DiagramTheme) throws -> MDVMermaidPrepared  // parse → repair → layout (ELK)
static func rasterize(_ p: MDVMermaidPrepared, width: CGFloat, scale: CGFloat) -> NSImage?  // CoreText at final size, upright
static func displaySize(for p: MDVMermaidPrepared, width: CGFloat) -> CGSize  // whole points; shared by view and raster
```

**C-06.1 Source sanitisation (before parsing), in this order:**

| # | Rule | Reason |
| - | ---- | ------ |
| 1 | Drop a leading YAML front-matter block (`---` … `---`). | parser rejects it (`invalidHeader`) |
| 2 | xychart: `line "name" [...]`/`bar "name" [...]` → `line [...]`/`bar [...]`. | parser knows only the unnamed form |
| 3 | On `style`/`classDef`/`linkStyle` lines: expand `#rgb`/`#rgba` to 6/8 digits; map these CSS colour names (case-insensitive, only where they follow `fill:`, `stroke:` or `color:`) to hex: `white black red green blue yellow orange purple gray grey lightgray lightgrey darkgray silver pink lightblue lightgreen lightyellow gold teal navy maroon olive cyan magenta brown beige ivory lavender coral salmon tomato crimson indigo violet khaki tan wheat mintcream honeydew aliceblue whitesmoke gainsboro snow`, plus `transparent` and `none` → `#00000000`. Any other name is passed through (and renders black). | 3-digit hex and names render **black** |
| 4 | stateDiagram: fold every `ID: text` description line for an ID into one `state "a<br/>b" as ID` alias inserted after the header. | parser keeps only the first registration |
| 5 | `id[/text/]` and `id[\text\]` (parallelograms) → `id[text]`. | not in the parser's shape table |
| 6 | Strip inline formatting tags `<b> <i> <u> <s> <strong> <em> <small> <sup> <sub> <span> <code> <tt> <font> <mark>` (open and close), keeping their content; leave `<br/>`. | rendered literally |

**C-06.2 Post-parse and post-layout repairs:**

| Diagram | Repair |
| ------- | ------ |
| flowchart, stateDiagram | Subgraph ownership: a node listed in several subgraphs belongs to the **last** one (Mermaid.js semantics); it is removed from the others. (Prevents the ELK `assert`, E-01.) |
| stateDiagram | `classDef`, `class A,B name`, and `style` lines read from the source are applied to the model (`classDefs`, `classAssignments`, `nodeStyles`). |
| flowchart, stateDiagram | Whole-label `$$…$$` nodes: label replaced by a blank placeholder measured to the math image's size; image composited after rasterising, centred, at a pixel-snapped origin (R-15, I-009). |
| sequenceDiagram | `<br>` → newline in notes; → space in actor labels; message labels with `<br>` are blanked and drawn by mdv, lines stacked upward from the arrow (13 pt pitch, 11 pt font, muted colour). |
| sequenceDiagram | Actor gaps widened until every message label fits between its endpoints (+ 24 pt; self-messages + 36 pt); all x coordinates remapped piecewise-linearly through old→new actor centres. |
| sequenceDiagram | Multi-line message rows: the message and everything below shifted down $(n-1) \times 13 + 4$ pt; spanning blocks, lifelines, and the diagram height grow. |
| sequenceDiagram | A block whose last item is a note is extended to enclose it (+ 8 pt). `autonumber` draws a filled disc ($r = 8$ pt) with the 1-based index at each arrow's tail. |

**C-06.3 Document theme.** The *Document* style derives a `DiagramTheme` from the active `MDVTheme`: background = code-block background, foreground = text colour, node surface = page colour mixed 25 % toward the code background on light themes (lifted 16 % toward foreground on dark), lines/borders/muted = fixed mixes of background and foreground.

### C-07 LaTeX math

**C-07.1 Rewriting.** `MathMarkdown.rewrite(block, fontSize, headingSizeEms, color)` replaces each math span in a prose block with an image reference

```
![](mdv-math://inline/<base64url(latex)>?s=<size pt, 1 decimal>&c=<RRGGBBAA>)     // $…$ only
![](mdv-math://display/<base64url(latex)>?s=…&c=…)                                // every $$…$$, own line or mid-line
```

The host selects the typesetting mode (K-08: `inline` → `.text`, `display` → `.display`) and is decided by the delimiter alone. Placement is a separate rule: a `$$…$$` whose opening is at line start and closing at line end is emitted as its **own paragraph** (blank lines inserted, indentation preserved) so MarkdownUI's block-image path renders it centred via `MathDisplayView`; every other span — `$…$`, and a `$$…$$` mid-line — is an inline image via `MathInlineImageProvider`, so a mid-line `$$\sum_{i=1}^n$$` shows display-style limits inside the sentence. `base64url` is RFC 4648 §5 without `=` padding; decoders MUST re-pad to a multiple of four. Delimiter rules (Pandoc `tex_math_dollars`): an opening `$` is followed by non-whitespace; a closing `$` is preceded by non-whitespace and not followed by a digit; a span contains no bare `$` and never crosses a backtick; `\$` is literal; fenced blocks and inline code are never rewritten; an empty `$$` pair is literal.

**C-07.2 Typesetting.** `MathImageCache.rendered(for: MathSpec)` typesets with `MathImage(latex, fontSize, textColor, labelMode: display ? .display : .text)` after (a) registering the extra symbols and (b) applying the rewrites below, and bakes the result to a bitmap at the screen scale (I-008). Cache: 2048 entries keyed by the URL.

| (a) Registered symbols (Latin Modern Math has the glyphs) | (b) Command rewrites (regex, in order) |
| --- | --- |
| relations: `gtrsim lesssim gtrapprox lessapprox leqslant geqslant lll ggg nless ngtr nleq ngeq doteq triangleq therefore because implies impliedby models vDash Vdash nparallel nmid subsetneq supsetneq nsubseteq nsupseteq sqsubseteq sqsupseteq precsim succsim`; arrows: `hookrightarrow hookleftarrow rightharpoonup leftharpoonup rightleftharpoons leftrightharpoons nearrow searrow swarrow nwarrow longmapsto twoheadrightarrow rightsquigarrow leadsto rightrightarrows leftleftarrows`; ordinary: `dots dotsc dotsb varnothing hslash mho Box square blacksquare bigstar checkmark ddagger S P pounds copyright degree beth gimel wp nexists complement # _`; big operators: `iint iiint oiint bigsqcup bigodot bigotimes biguplus`; binary: `intercal leftthreetimes rightthreetimes divideontimes` | `\operatorname{X}` / `\operatorname*{X}` → `\mathrm{X}`; `\dfrac`/`\tfrac` → `\frac`; `\boldsymbol` → `\bm`; `\bmod` → `\;\mathrm{mod}\;`; `\pmod{n}` → `\;(\mathrm{mod}\;n)`; `\not=` → `\neq`; `\big \Big \bigg \Bigg` (with optional `l r m`) before a delimiter → removed; `\coloneqq` → `:=`; `align*`/`equation*`/`gather*`/`multline*` → unstarred; `align` → `aligned`; `multline` → `gather`; `\begin{equation}`/`\end{equation}` → removed |

`\boxed{…}` is implemented in the vendored SwiftMath (`MTBoxed` atom, `MTBoxDisplay`: frame of fraction-rule thickness with $0.35\,\mathrm{em}$ padding). Unsupported and shown as source: `\underbrace`, `\overbrace`, `\stackrel`, `\substack`, `\&`.

**C-07.3 Plain-text form** (`MathMarkdown.plainText`), used by the TOC, bookmark titles, and mixed Mermaid labels: same delimiter rules; `\frac{a}{b}` → `a/b`, `\sqrt{x}` → `√x`, wrappers (`\text \mathrm \mathbf \mathit \mathcal \mathbb \operatorname \boldsymbol \bm \hat \vec \bar \tilde`) → their content; `^`/`_` followed by a character or `{…}` → Unicode super/subscript when every character has one (digits, `+ - n i` / `+ - i j n k x`), else kept verbatim; Greek letters, common relations/operators/arrows/sets → Unicode; unknown commands → their name; braces removed; whitespace collapsed.

### C-08 Anchors: bookmarks and scroll positions

```sql
CREATE TABLE bookmarks (id INTEGER PRIMARY KEY, path TEXT NOT NULL, title TEXT NOT NULL,
    sort_order INTEGER NOT NULL, created_at INTEGER NOT NULL,
    block_index INTEGER NOT NULL DEFAULT 0, block_fingerprint TEXT NOT NULL DEFAULT '');
CREATE TABLE scroll_positions (path TEXT PRIMARY KEY, block_index INTEGER NOT NULL,
    block_fingerprint TEXT NOT NULL, updated_at INTEGER NOT NULL, file_mtime INTEGER NOT NULL DEFAULT 0);
```

`fingerprint(block)` MUST split `block` at every Unicode whitespace scalar, discard empty pieces, join the pieces with U+0020 SPACE, apply locale-independent Unicode lowercase without compatibility or canonical normalization, and retain the first 80 extended grapheme clusters. `resolve(blocks, storedIndex, fingerprint)` = the first block whose fingerprint equals the stored one; else `storedIndex` clamped to $[0, |\mathrm{blocks}|-1]$; else 0 for an empty document. A scroll position is restored only when the stored anchor resolves **and** the file's modification time is within 1 s of the stored `file_mtime` **and** the index is in bounds (E-08).

### C-09 Theme contract (`MDVTheme`), the fields behaviour depends on

```swift
struct MDVTheme {
    let id: String; let isDark: Bool
    let text, secondaryText, tertiaryText, heading, strong, link, accent, background, secondaryBackground, border, divider, blockquoteBar: Color
    var bodyFontFamily: FontFamily; var baseFontSize: CGFloat            // default 16
    var h1SizeEm = 1.75, h2SizeEm = 1.4, h3SizeEm = 1.15; h4SizeEm 1.0, h5SizeEm 0.875, h6SizeEm 0.85 (fixed)
    var headingSizeEms: [CGFloat]     // [h1…h6], used by markdownTheme and by math in headings (R-13)
    var articleMaxWidth: CGFloat?; var articleHorizontalPadding: CGFloat
    var smartTypographyAllowed: Bool  // false for phosphor, standard-erin-light, standard-erin-dark
    var codePalette: CodePalette?     // default: oneDark (dark) / githubLight (light)
}
static let all = [highContrast, sevilla, charcoal, solariumDaylight, solariumMoonlight, phosphor, twilight, standardErinLight, standardErinDark]
```

Code blocks always use the system monospace face regardless of `bodyFontFamily` (`TYPOGRAPHY.md`).

### C-10 Smart typography (`smartenMarkdown`)

Applied to one block; the block is returned unchanged if it is a fence, looks like a GFM table (a `|---|` separator row), or is a thematic-break line. Otherwise, outside inline code spans (a run of $n$ backticks closes only on a run of exactly $n$), link/image URL parts (`](` … matching `)`), and `<…>` spans: `"` and `'` → directional quotes chosen from the preceding character; `---` → `—`; `--` between letters/digits → `–`; ` -- ` → ` — `; other `--` runs unchanged (CLI flags survive); `...` → `…`.

### C-11 Heading slug

`slug(s)` = lower-case `s`; keep letters and digits; keep `-` and `_` when something precedes them; drop every other non-whitespace character; **every** run of whitespace becomes one `-` when something precedes it — including a run that follows a `-` or a dropped character, so that `a - b` → `a---b` and `C++ & Rust` → `c--rust` as on GitHub; strip trailing `-`/`_`. Applied to both the link fragment and `TOCHeading.slugText`; equality selects the target, and when several headings share a slug the **first in document order** wins. GitHub's numeric disambiguation suffixes (`-1`, `-2`) are not generated (D-17).

### C-12 Section and inline-stripped text

`section(headingAt i)` = blocks $[i, j)$ where $j$ is the index of the next **TOC heading** (C-02 rule 7 — an h4–h6 or setext heading never ends a section) with level $\leq$ the level of $i$, or the block count. Copy output = those blocks joined with `\n\n`. `stripInlineMarkdown` removes trailing `#`s, `**`, `__`, backticks, unescaped `*`, **both** underscores of an `_…_` emphasis pair whose opening `_` is not preceded by a letter or digit (word-internal underscores such as `snake_case` are kept), and reduces `[text](url)` to `text`.

### C-13 Build outputs (`build.sh`)

```
swift build -c {debug|release}
build/mdv.app/Contents/{MacOS/mdv, Info.plist, Resources/{AppIcon.icns, *.otf, *-highlights.scm,
                        mathFonts.bundle/, mdv, Help.md}}
codesign --force --sign - --entitlements mdv/mdv.entitlements build/mdv.app     # ad hoc
```

The vendored SwiftMath resolves `mathFonts.bundle` from `Bundle.main` first and from `Vendor/SwiftMath/mathFonts.bundle` (by `#filePath`) when running unbundled (`swift run`).

### C-15 History persistence (`mdv_history`)

```json
[ { "id": "<UUID>", "path": "/abs/path/to/file.md", "addedAt": <seconds since 2001-01-01 as Double> }, … ]
```

Swift `Codable` encoding of `[HistoryEntry]` (`id: UUID`, `path: String`, `addedAt: Date`, keys as shown, default `JSONEncoder` date strategy). Order is most recent first. `filename` is derived (last path component), not stored. A value that fails to decode MUST yield an empty history, never a crash; unknown keys MUST be ignored.

### C-16 Remote-image network contract

When `mdv_load_remote_images` is true, a remote image MUST be fetched with an ephemeral `URLSession` that has no persistent cache, cookie storage, credential storage, or shared authentication state. The request MUST be an unauthenticated `GET` to the document-provided `http` or `https` URL; it MUST send no `Cookie`, `Authorization`, or `Referer` header. The only document-derived request data MAY be the original URL and the sequence of redirect URLs. Redirects MUST be followed at most five times and only while every target remains `http` or `https`; any other redirect MUST fail. Connection timeout is 15 s and total resource timeout is 30 s. The body MUST be streamed and cancelled as soon as it exceeds 32 MiB. A successful response MUST have a 2xx status, an `image/*` media type, and decode through ImageIO within K-14. Any violation MUST produce the E-11 failure placeholder. No response body or decoded remote image may be written to disk.

### C-17 Render harness and corpus

The executable name is `render-harness`; every invocation runs as `swift run --package-path tools/render-harness render-harness …` from the repository root.

| Invocation | Behaviour | Exit |
| ---------- | --------- | ---- |
| `render-harness INPUT --output FILE [--width PT] [--scale S]` | Render one `.md` document or one raw `.mmd` diagram to PNG. Defaults: width 860 pt, scale 2. The parent directory of `FILE` MUST exist; the command MUST NOT create it. | 0 success; 1 render/fallback failure; 2 usage, unreadable input, or unwritable output |
| `render-harness --scan ROOT --output-dir DIR` | Recursively discover non-hidden `.mmd` files and Mermaid fences in `.md` files, ordered by the UTF-8 bytes of relative path and then fence index. Render each case to a collision-free relative PNG path under `DIR`; raw `.mmd` is one case. Unsupported diagram types declared by E-02 count as expected fallbacks; every other fallback is a failure. | 0 when every case has its expected result; 1 when any case fails; 2 for usage or I/O failure |
| `render-harness --check MANIFEST [--case ID]` | Execute every manifest case, or exactly `ID`, compare dimensions and pixels with its golden when present, and evaluate its named metric. Cases MUST run in manifest order. | 0 when all selected cases pass; 1 for any mismatch or render failure; 2 for invalid manifest, unknown `ID`, usage, or I/O failure |

`test-docs/render-cases.json` MUST be UTF-8 JSON with this shape; paths are repository-relative, ids are unique, and unknown keys are ignored:

```json
{
  "version": 1,
  "cases": [
    {
      "id": "unique-string",
      "input": "test-docs/example.md",
      "kind": "markdown-or-mermaid",
      "width": 860,
      "scale": 2,
      "expect": "render-or-fallback",
      "golden": "test-docs/goldens/example.png",
      "metric": "pixel-or-ink-or-sequence-layout"
    }
  ]
}
```

For a pixel comparison, let $N$ be the number of pixels in either equal-sized image and let $D$ be the pixels for which at least one 8-bit RGBA channel differs by more than 8. The mismatch fraction is

$$
q = \frac{|D|}{N}.
$$

The comparison MUST pass when $q \leq 0.001$; $N=0$, unequal dimensions, a missing golden, or a missing output is a failure. `ink` uses §7.1. `sequence-layout` checks the geometric assertions in T-19. Each case MUST emit one JSON object on stdout with `id`, `status` (`pass`, `fail`, or `fallback`), and `output`; human-readable diagnostics go to stderr. Case output MUST be byte-for-byte stable for identical inputs, dependencies, width, scale, and backing environment.

## 5. Interface specification

### 5.1 GUI: menus and shortcuts

| Menu · item | Shortcut | Effect | Errors / disabled |
| ----------- | -------- | ------ | ----------------- |
| mdv · Install Command Line Tool… | — | Symlink `/usr/local/bin/mdv` → `Contents/Resources/mdv`: unprivileged attempt first, then an AppleScript *with administrator privileges* auth dialog | every outcome is an `NSAlert` (C-14): *CLI helper missing*, *Already installed*, *Install failed* (with the error message), *Command line tool installed*; cancelling the auth dialog leaves the symlink untouched with no alert |
| File · Open… | ⌘O | Open panel; loads into this window (R-01) | cancel: no-op |
| File · Open in New Window… | ⌘⇧O | Open panel; new window | — |
| File · Edit · Edit Current File | ⌘E | Open current file in the chosen editor (R-23) | no editor: prompts to choose; launch failure: `NSAlert` "Couldn't open in external editor" with *Choose Different Editor…* / *Cancel* (C-14) |
| File · Edit · Choose Editor… / Forget Editor | — | Set / clear `mdv_editor_app_path` | — |
| Edit · Find… | ⌘F | Find bar, or global search when the sidebar was last focused (R-24) | — |
| Edit · Search History… | ⌘⇧F | Focus global search (R-25) | — |
| Edit · Copy / Select All | ⌘C / ⌘A | System pasteboard group: act on the focused view's text selection (R-22) | — |
| Navigate · Back / Forward | ⌘← / ⌘→ | History stacks (R-18) | always enabled; no-op when the stack is empty |
| View · Show/Hide Sidebar | ⌃⌘S | Toggle history sidebar (R-20) | — |
| View · Zoom In / Zoom Out / Actual Size | ⌘= / ⌘- / — | R-30 | Zoom In / Out disabled at the clamps; Actual Size disabled at 1.0 |
| View · Smart Typography | — | Toggle R-17; label reads "(off for this theme)" and is disabled when the theme opts out | — |
| View · Load Remote Images | — | Toggle R-16 | — |
| Bookmarks · Bookmark Current Spot | ⌘D | R-27 | — |
| Bookmarks · Set Placeholder / Jump to Placeholder | ⌘⇧0 / ⌘0 | R-28 | Jump always enabled; beeps when no placeholder |
| Bookmarks · slot 1…5 | ⌘1…⌘5 | Open numbered bookmark (R-27) | disabled when the slot is empty; beeps when the bookmark's file is missing (E-09) |
| Help · mdv Help | ⌘? | R-31 | — |
| Find bar | ⌘G / ⇧⌘G / Esc | next / previous / close (R-24) | stepping disabled with no matches |
| Toolbar | — | Theme picker (nine themes + System), inspector toggle, Open, Edit | — |

In-block controls: code blocks — hover toolbar (wrap, copy), context menu (Copy Code, Wrap Long Lines, Copy Without Prompts when applicable); Mermaid blocks — hover capsule (style menu, show source, export PNG, copy) and context menu (Copy Code, Show Mermaid Source / Show Diagram, Diagram Style, Export Diagram as PNG); display math — context menu (Copy LaTeX). PNG export writes the diagram at natural size, $2\times$ pixel density, to a user-chosen path; failure beeps.

### 5.2 CLI: `bin/mdv`

| Invocation | Behaviour | Exit |
| ---------- | --------- | ---- |
| `mdv` | `open <app>` | 0 |
| `mdv FILE…` / `mdv DIR` | Each argument resolved to an absolute path; `open -a <app> <paths…>` (the app receives them via LaunchServices, R-01/R-02) | 0; `1` + `mdv: no such file: <arg>` on stderr for the **first** argument that does not exist (later arguments are not checked; nothing opened) |
| `mdv -` | Only as the sole argument: stdin copied to `$(mktemp -t mdv-stdin).md`, then opened. `mdv - FILE` treats `-` as a filename (`no such file: -`, exit 1) | 0 |
| `mdv -h` / `--help` | Usage text (lines 2–9 of the script) to stdout | 0 |
| `mdv --version` | `CFBundleShortVersionString` from the located bundle's `Info.plist` | 0 |
| any (including `--help`/`--version`), bundle not found | `mdv: mdv.app not found (set MDV_APP or install to /Applications)` on stderr — the bundle is located before the arguments are read | 1 |

Bundle search order: `$MDV_APP` (if a directory) → `/Applications/mdv.app` → `~/Applications/mdv.app` → `../build/mdv.app` and `../mdv.app` relative to the script → `mdfind "kMDItemCFBundleIdentifier == 'com.mdv.app'"` (first hit).

### 5.3 Build and release: `make`

| Target | Effect |
| ------ | ------ |
| `make` / `build` | `deps` check (Swift $\geq$ 5.9, macOS $\geq$ 13, `build.sh` executable) then `./build.sh debug` → `build/mdv.app` (C-13) |
| `release` | `./build.sh release` |
| `run` | build + launch |
| `install` | copy to `/Applications/mdv.app`, `lsregister -f`, then `install-cli` (sudo symlink `/usr/local/bin/mdv` → `bin/mdv`) |
| `uninstall` | remove the symlink and `/Applications/mdv.app` |
| `register` | `lsregister -f build/mdv.app` |
| `clean` | remove `build/`, `.build/`, and `build_icon/` |
| `dist` | `check-version` MUST require an exact `vX.Y.Z` tag on `HEAD` and MUST reject an absent, malformed, or command-line-overridden version before `clean` or any build step (R-34) → `clean` → `release` → `sign` (Developer ID, hardened runtime, timestamp; `codesign --verify --deep --strict`) → `zip-notary` → `notarize` (keychain profile) → `staple` → `zip-release` → `checksum` (`.sha256`) → `verify-release` (`spctl`) |
| `github-release` | upload the zip and checksum to the GitHub release for the tag |
| `icon` | regenerate `mdv/AppIcon.icns` from `MDV.png` |

Release inputs (Makefile variables, overridable on the command line): `TEAM_ID` and `CERT_NAME` (Developer ID identity; `sign` exits 1 when empty — the checked-in defaults name the repository owner's identity and MUST be overridden by any other release engineer), `NOTARY_PROFILE` (default `mdv-notary`; `notarize` exits 1 when empty), and `NOTES_FILE` (optional release notes for `github-release`). `VERSION` is derived only from the exact tag and is not an overridable release input.

CI (`.github/workflows/build.yml`): on every push to `main`, every pull request, and manual dispatch, build `debug` and `release` on `macos-15`, verify the bundle layout, and upload `mdv-release.tar.gz`; on a push to `main` only, publish it as the rolling `latest` prerelease.

### 5.4 Cross-cutting: diagnostics and failure reporting

| ID | Contract |
| -- | -------- |
| **R-35** (above) | Nothing document-derived is logged. |
| **C-14** | Failures arising from **document content** are reported in place, never modally: unrenderable diagram / math → fallback text in the block (R-10, R-14); missing or blocked image → placeholder in the block (R-16); unreadable file → the window stays on its previous content (E-03); missing bookmark file → row marked as missing in the inspector, and opening it beeps (E-09). Failures of a user-initiated system action are reported by a beep (PNG export, R-09) or an `NSAlert` (CLI install outcomes; external-editor launch failure, R-23) — the only two modal dialogs the application shows besides open/save panels and the editor chooser (§5.1). |

## 6. Invariants (must hold in every valid implementation)

| ID | Invariant |
| -- | --------- |
| **I-001** | Rendering is pure in its inputs: the same file bytes, theme, zoom, preferences, window content width, and backing scale produce the same blocks, TOC, and rendered output; no render path reads the network except the C-16 remote-image fetch gated by R-16. |
| **I-002** | The application MUST NOT terminate because of document content admitted by K-14. Every third-party parser is reached only after the applicable limit check and sanitiser (C-06.1, C-07.1/2), and every detected parse/layout failure becomes a fallback block. |
| **I-003** | Document content MUST NOT reach a log, subprocess, or network request except that C-16 MAY disclose the original remote-image URL and permitted redirect URLs after the reader enables R-16. No other document bytes may enter request headers or bodies. The only other externally visible document-derived artefacts are the user's pasteboard on explicit copy, a user-chosen PNG on export, and `mdv.db`. The in-process `mdv-math://` scheme is not external. |
| **I-004** | The block split (C-02) is computed at most once per distinct `raw` string per load; `blocks[i]` is stable for the life of the document, so block indices used by find, TOC, heading copy, bookmarks, and scroll anchors refer to the same text. |
| **I-005** | Every mermaid raster is displayed at exactly its own point size — `displaySize(for:width:)` is the single source of both the bitmap size and the view frame — so the diagram is never resampled by the view layer. |
| **I-006** | All access to `mdv.db` goes through one connection opened `FULLMUTEX`, in WAL mode; concurrent use from the history re-index queue and the main thread is serialised by SQLite, never by the caller. |
| **I-007** | Persistence writes are whole-row `INSERT … ON CONFLICT DO UPDATE` or single-statement updates; a crash mid-write leaves the previous row, never a partial one. |
| **I-008** | Every `NSImage` handed to SwiftUI `Text`/`Image` for math is bitmap-backed (not drawing-handler-backed); idle CPU with math on screen is that of a static page. |
| **I-009** | Math drawn inside a Mermaid raster is drawn at a pixel-aligned origin; its ink weight, per the formula in §7.1, is at least $0.9\times$ that of the same expression typeset for the document at the same size and scale. |
| **I-010** | Heading slugs (C-11) are computed from the un-mathed heading text, so `#fragment` links written for GitHub resolve identically whether or not the heading contains `$…$`. |
| **I-011** | The vendored SwiftMath carries exactly the patches listed in `Vendor/SwiftMath/README.md`; everything else is byte-identical to upstream v1.7.3. |
| **I-012** | Smart typography never changes bytes inside code spans, fences, link URLs, `<…>` spans, GFM tables, thematic breaks, or math. |
| **I-013** | The history list never exceeds 100 entries and never contains duplicates; the path most recently added by an adding route is first, and a selecting route never changes that order. |

## 7. Constraints (precise and measurable)

| ID | Constraint |
| -- | ---------- |
| **K-01** | Platform: macOS $\geq$ 13.0, Apple Silicon or Intel; toolchain: Swift $\geq$ 5.9 (`swift-tools-version: 5.9`); no Xcode project — `swift build` + `build.sh` only. |
| **K-02** | Bundle: `CFBundleIdentifier com.mdv.app`; version `1.0.0` (1); not sandboxed; entitlement `files.user-selected.read-only`. |
| **K-03** | History cap 100 entries. Global search returns at most 80 hits; snippets are 14 tokens. Bookmark hot-key slots: 5. |
| **K-04** | Zoom: step $0.10$, range $[0.60, 2.50]$, default $1.0$. Sidebar width $[180, 400]$ pt (not persisted); inspector width $[180, 520]$ pt (persisted, default 240); bookmarks pane $\geq 120$ pt with the TOC keeping $\geq 80$ pt. |
| **K-05** | Highlighted languages: C, Go, Rust, Bash, JavaScript, YAML, TOML, Python, Ruby (grammar commits pinned in `mdv/Grammars/README.md`); Swift and SQL are required additions (R-38). |
| **K-06** | Live-reload event latency: 50 ms (no deferral, R-05); transient zero-byte re-read: 500 ms (D-18). Heading-copy flash: 0.6 s. Zoom HUD: 0.9 s. Scroll-restore mtime tolerance: 1 s (the stored `file_mtime` is truncated to whole seconds, C-08); index mtime gate (R-26): whole seconds, equality. Bookmark-title heading look-back: 40 blocks; bookmark-title fallback: 60 extended grapheme clusters (R-27). |
| **K-07** | Mermaid raster width MUST use exactly the §7.2 formula, including its 1 pt lower bound, at the screen backing scale; pinch zoom is clamped to $[0.5, 4]$; zoomed container height is $\leq 540$ pt. Caches: 96 layouts, 192 rasters, 192 MB. |
| **K-08** | Math: `$…$` spans typeset in `.text` style, every `$$…$$` span in `.display` whether on its own line or mid-line (C-07.1); diagram-label math at 16 pt; message-label line pitch 13 pt; sequence row height 40 pt (library) grown by $(n-1)\times 13 + 4$ pt for $n$-line labels. Cache: 2048 images. |
| **K-09** | Fingerprints: 80 extended grapheme clusters after the C-08 normalization. FTS tokenizer `unicode61 remove_diacritics 2`. |
| **K-10** | Typography defaults: body 16 pt, line spacing $0.30\,\mathrm{em}$, heading scales $h_1=1.75$, $h_2=1.40$, and $h_3=1.15$, article max width 860 pt (the cap on the **padded** article frame, K-13), gutter 40 pt (per-theme overrides in `TYPOGRAPHY.md`). |
| **K-11** | Release artefacts: `dist/mdv-<version>-macos.zip` + `.sha256`, Developer ID signed with hardened runtime and timestamp, notarised and stapled; `<version>` equals the tag without `v`. |
| **K-12** | Ad-hoc-signed development bundles MUST pass `codesign --verify --deep --strict`; nothing may be placed at the bundle root besides `Contents/`. |
| **K-13** | *Column width* $w_{\mathrm{col}}$ (used by R-11, K-07): the width a block's content is laid out in, per the formula in §7.2. The cap applies to the padded article frame **before** the paddings are subtracted, so with the K-10 defaults a wide window gives $w_{\mathrm{col}} = 860 - 80 - 12 = 768$ pt and a Mermaid raster of $732$ pt. |
| **K-14** | Untrusted-content ceilings, measured before the named operation: UTF-8 document file 64 MiB; one Mermaid source 1 MiB; one LaTeX span 64 KiB; encoded or compressed local/data/remote image 32 MiB; decoded image 64 megapixels, 256 MiB, and 16,384 pixels on either axis. MiB and KiB are binary units. C-16 additionally limits redirects and time. Content at the ceiling is admitted; content above it follows E-28. |
| **K-15** | Idle-math CPU protocol: after `test-docs/math.md` has been visible and untouched for 5 s, collect 30 one-second process-CPU samples with no pointer, keyboard, window, appearance, or file activity on an otherwise idle `macos-15` host. The median MUST be $\leq 1\,\%$ and the nearest-rank 95th percentile MUST be $\leq 3\,\%$. |

### 7.1 Ink-weight metric (I-009, T-17)

Let $P$ be the pixels of a crop, at $2\times$ backing scale, whose bounds are the math image's rectangle enlarged by 4 px on each side, composited on white; $g(p) \in [0, 255]$ the luminance of pixel $p$; and $D = \{\, p \in P : g(p) < 200 \,\}$ the inked pixels. Then

$$
\mathrm{ink}(P) = \frac{1}{|D|} \sum_{p \in D} \bigl(255 - g(p)\bigr), \qquad \mathrm{ink}(P) = 0 \text{ when } D = \varnothing .
$$

I-009 holds when $\mathrm{ink}(P_{\mathrm{node}}) \geq 0.9 \cdot \mathrm{ink}(P_{\mathrm{doc}})$ for the same LaTeX at the same font size; an empty $D$ on either side is a failure.

### 7.2 Column width (K-13, R-11, T-18)

Let $w_{\mathrm{area}}$ be the window's content width; $w_{\mathrm{side}}$ and $w_{\mathrm{insp}}$ the history sidebar and inspector widths **plus their 8 pt drag handles** when shown, and $0$ when hidden; $w_{\max}$ the theme's `articleMaxWidth`, or $\infty$ when the theme sets none; $p$ the theme's `articleHorizontalPadding`; and $b = 6$ pt the per-block horizontal padding. Then

$$
w_{\mathrm{col}} = \min\bigl(w_{\mathrm{area}} - w_{\mathrm{side}} - w_{\mathrm{insp}},\; w_{\max}\bigr) - 2p - 2b .
$$

A Mermaid raster is drawn at $\lfloor \min(\text{natural}, \max(w_{\mathrm{col}} - 36, 1)) \rfloor$ pt (R-11, K-07).

## 8. Edge cases and failure semantics

| ID | Case | Semantics |
| -- | ---- | --------- |
| **E-01** | Mermaid node listed in two subgraphs (`A --> B` inside `subgraph X`, `B` declared in `subgraph Y`). | Ownership normalised to the last subgraph before layout (C-06.2); renders. Without this the ELK importer's `assert` aborts the process — the historical launch-crash. |
| **E-02** | Mermaid diagram type the library lacks (`timeline`, `gantt`, `pie`, `mindmap`, `gitGraph`, …), or any other parse error. | Fallback block: "Mermaid diagram could not be rendered" + source. |
| **E-03** | File unreadable (permissions, not UTF-8, vanished between open and read) — on any route, including a sidebar row or ⌘← whose file was deleted since. | Load aborted; with a previous document, the window keeps that document, selection, and watcher and no history entry is added or moved. With no previous document, the window enters `EMPTY`; an initial history-head row remains in history and later rows are not tried (R-40). |
| **E-04** | Directory with no Markdown files. | Nothing loads; no history change. |
| **E-05** | Link to a local Markdown path that does not exist. | Handed to the system opener (which reports the failure); no navigation. |
| **E-06** | Fragment with no matching heading slug, or invalid UTF-8 percent encoding. | A same-document fragment is a no-op. A local path plus fragment still loads the target but remains at its top; R-06 restoration is suppressed (R-19). No error is shown. |
| **E-07** | `$` in prose that is not math: `$5 and $10`, `$5-$10`, `$100/month`, `\$x\$`, `$HOME` in code, an empty `$$`. | Left literal by the delimiter rules of C-07.1 (opening followed by space, closing before space or followed by a digit, backtick crossing, escape, empty span). |
| **E-08** | Bookmark or scroll anchor whose block moved or changed. | Resolve by fingerprint first, then clamped index (C-08); a scroll position is discarded (start at top) if the file's mtime differs by more than 1 s or the index is out of bounds. |
| **E-09** | Bookmark whose file no longer exists. | Row shown as missing in the inspector; opening it by row or numbered shortcut beeps and does nothing else; the row remains until removed. |
| **E-10** | LaTeX SwiftMath rejects (unknown command, unbalanced braces). | Source shown in monospace at $0.9\times$ size (inline) or with the parser's message (display); never blank. |
| **E-11** | Remote image loading disabled; or enabled but redirect, timeout, status, media type, byte ceiling, decode, or image-dimension validation fails. | Disabled: "Remote image blocked" placeholder that reveals the View menu item. Enabled failure: an explicit failure placeholder; partial bytes are discarded and no response body is persisted (C-16). |
| **E-12** | `mdv.db` cannot be opened or a statement fails. | `NSLog("[mdv] …")`; the feature degrades (no search hits, no bookmarks, no scroll restore); viewing continues. |
| **E-13** | Mermaid `<br>` in a sequence message that makes the label wider than its actors' gap, or taller than a row. | Gap widened and rows expanded per C-06.2; labels never cross a lifeline they don't span and never overlap the previous arrow. |
| **E-14** | Mermaid `style … fill:#eee` / `fill:white`. | Normalised to 6-digit hex (C-06.1) — rendered as the intended colour, not black. |
| **E-15** | `xychart` with `line "name" [...]`. | Series rendered; legend shows `Line n` (the library has no series name field). |
| **E-16** | Math that is the *entire* content of a table cell or list item. | Rendered through the block-image path at body size (the mode still follows the delimiter, K-08), leading-aligned, not centred (MarkdownUI routes image-only paragraphs there). |
| **E-17** | The find query matches inside a code fence, a `$$` math fence, a GFM table, or any block that contains `![`. | Block tinted as a whole; no character-level highlight. Every other block is inline-highlighted per R-24, so an occurrence that lies only inside markup (`**bold**`'s asterisks, a link URL, a `#` marker) is counted in $m$ but not marked, and a heading containing `$…$` shows its LaTeX source while the find bar is open. |
| **E-18** | ⌘F while the history sidebar has focus. | Routes to global search (R-24), not the document find bar. |
| **E-19** | Reload of the current file while text is selected. | Scroll position kept; the text selection is not preserved. |
| **E-20** | Same file opened in two windows and edited on disk. | Each window's watcher reloads independently; scroll positions are per path, last writer wins. |
| **E-21** | The displayed file is deleted, replaced by an atomic-rename save, or read mid-save as empty / not UTF-8. | Rename: reload with the new content (R-05). Delete without re-creation, or an undecodable read: content and scroll position kept, no error, watch stays armed indefinitely; a later re-creation or completed write reloads. A zero-byte read while content is displayed: page kept, re-read after 500 ms, and that read is shown — so a file that really was emptied appears empty 500 ms after the event. |
| **E-22** | `#fragment` whose target is an h4–h6 heading or a setext (`===`/`---`) heading; a click or hover on such a heading. | Fragment: no-op — only `#`–`###` single-line ATX headings are targets (C-02, D-17). Click/hover: the heading is prose for R-22 — text-selectable, arrow pointer, no section copy. |
| **E-23** | Fence closed by a longer/shorter backtick run than the opener; a fenced block that is never closed; an indented (four-space) code block containing a blank line. | Splitter semantics of C-02 (fence, math-fence, and indented-code rules): closes on any run of the same three-character marker; runs to end of input; the indented block is split into two blocks and renders as two. |
| **E-24** | An empty or whitespace-only global search query. | No search is performed; the results list is empty (C-03). |
| **E-25** | Rendering in flight (diagram layout, math typesetting) when the document changes. | The in-flight task is cancelled; its result is discarded, never shown for the new document. |
| **E-26** | Two windows open (⌘⇧O) and a menu command (⌘O, ⌘F, ⌘D, ⌘←, ⌘E, …) or an open event (Finder, `open -a`, `bin/mdv FILE`) arrives. | Only the key window acts (R-01); the other window is unchanged — no second open panel, no second bookmark, no navigation, no file load. |
| **E-27** | ⌘0 (placeholder) or ⌘←/⌘→ (snapshot) whose file no longer exists on disk; a snapshot whose history row was removed. | Missing file: ⌘0 beeps and keeps the placeholder (as E-09); ⌘←/⌘→ beeps, discards that snapshot, and the view is unchanged. Removed row: the snapshot was already dropped (R-18), so ⌘← skips to the next one. |
| **E-28** | Untrusted content exceeds a K-14 ceiling. | Reject it before the applicable third-party parser or decoder. An oversized document load aborts exactly as E-03. Oversized Mermaid or LaTeX shows the R-10/R-14 source fallback with "input exceeds limit". An oversized image shows the E-11 failure placeholder. A remote request is cancelled as soon as its body crosses the ceiling; partial bytes and partial decoded output are discarded. Viewing other blocks continues. |

## 9. Acceptance criteria, tests, and evals

### 9.0 Status and target

The repository currently has **no automated test target**; the product direction is that it MUST get one (R-37, D-01 confirmed). Until it lands, every test below is a reproducible manual or scripted check against `build/mdv.app` or the C-17 offscreen render harness, which together with the raw diagram corpus and manifest MUST live in the repository (`tools/render-harness/`, `test-docs/mermaid/`, `test-docs/render-cases.json`; R-39 — *not yet checked in*). "Renders" means: the C-17 case reaches its declared `render` expectation, produces the required output, and leaves no crash report in `~/Library/Logs/DiagnosticReports/mdv-*.ips`.

The intended shape of the suite, so that each manual test below has a home to move to:

| Group | Target | What moves there | Runs |
| ----- | ------ | ---------------- | ---- |
| **Unit** (`Tests/mdvTests`) | pure functions: `ParsedDocument.parseBlocks/parseTOC`, `Database.makeFTSQuery`, `MathMarkdown.rewrite/plainText`, `MathSymbols.preprocess`, `MDVMermaidPipeline.sanitize/mergeStateDescriptions/normalizeColors`, `bookmarkFingerprint/resolveBookmarkAnchor`, `smartenMarkdown`, `headingSlug`, `sectionRange`, `CodeRenderer.SupportedLanguage.resolve` | T-07 (delimiter cases), T-10 (typography cases), T-14..T-16, T-20 (sanitiser output), T-22 (slugs), T-24 (query building), T-26 (anchors), T-30 (section ranges) | `swift test`, CI on every push |
| **Render snapshot** (`Tests/mdvRenderTests`) | `MDVMermaidPipeline.prepare/rasterize`, `MathImageCache`, `CodeRenderer.render` against the C-17 corpus and manifest; PNG comparisons use C-17's dimensions and $q \leq 0.001$ rule | T-06, T-13, T-17 (ink measurement), T-18, T-19 | `swift test`, CI (macOS runner) |
| **Persistence** (`Tests/mdvTests`, temp DB) | `Database` with `databaseURL` pointed at a temp dir: index, search, bookmarks, scroll positions, corrupt-file behaviour | T-24, T-28, T-33 | `swift test` |
| **UI / manual** | menus, shortcuts, drag, live reload, zoom HUD, window behaviour | T-01..T-05, T-08, T-09, T-11, T-12, T-21, T-23, T-25, T-27, T-29, T-31, T-32, T-35, T-36, T-38, T-40 | by hand, or an XCUITest target later |

Prerequisites for the unit group: `Database.databaseURL` becomes injectable; the pipeline functions marked `private` in `MDVMermaidPipeline`/`MathMarkdown` become `internal` (`@testable import mdv`) — an executable target can be imported with `@testable` only when built for testing, so the app code SHOULD move to a library target (`mdvCore`) with a thin executable, which is also what lets the render tests link the pipeline without the harness's copy-paste.

### 9.1 Build, bundle, launcher (scripted)

| ID | Test |
| -- | ---- |
| **T-01** | Fresh clone, `make` → `build/mdv.app` exists with every file in C-13 present; `codesign --verify --deep --strict build/mdv.app` exits 0; `otool -l` shows a minimum OS of 13.0 and `Info.plist` the identifier/version of K-02. Proves R-34, K-01, K-02, K-12, C-01, C-13. |
| **T-02** | On an untagged commit, both `make dist` and `make dist VERSION=9.9.9` exit non-zero at `check-version` before `clean` or any build command runs. Proves R-34 and the negative gate of K-11. |
| **T-03** | `bin/mdv --version` prints `1.0.0`; `bin/mdv nope.md` prints `mdv: no such file: nope.md` to stderr and exits 1; `echo '# hi' \| bin/mdv -` opens a window showing "hi"; `MDV_APP=/nonexistent bin/mdv` falls through the search order. `bin/mdv a.md b.md`: both appear in history, `b.md` is displayed. Proves R-01, R-33, §5.2. |
| **T-04** | `open build/mdv.app test-docs/` loads `README.md` and the sidebar lists the other `.md` files. `chmod 000` a file and open it: the window keeps its previous document and history is unchanged. Drag a `.mkd` file onto the window: it opens; drag a `.pdf`: nothing happens; drag `a.md` and `b.md` together: only the first opens. A directory holding `B.md` and `a.md` and no README opens `a.md`; a hidden `.notes.md` is neither opened nor listed. Proves R-02, R-03, E-03, E-04 (an empty directory changes nothing). |
| **T-43** | In a disposable release checkout whose `HEAD` has exact tag `v1.2.3`, with valid signing and notarization credentials, `make dist` produces `dist/mdv-1.2.3-macos.zip` and its `.sha256`; the checksum verifies, `codesign --verify --deep --strict` and `spctl` succeed on the extracted app, `stapler validate` succeeds, and no artifact name contains a command-line version. Proves R-34 and K-11. |

### 9.2 Rendering (manual, `test-docs/`)

| ID | Test |
| -- | ---- |
| **T-05** | `test-docs/syntax.md`: every GFM construct renders (tables, task lists, footnotes, strikethrough). Proves R-07. |
| **T-37** | `test-docs/code.md` gains a `swift` block (a `struct` with a `@Published` property, a `guard let`, a string interpolation, a `// MARK:` comment) and a `sql` block (`CREATE TABLE`, a `SELECT … JOIN … WHERE` with a string literal, a `-- comment`): keywords, strings, comments, numbers, types and function names are each coloured differently from plain text, and a `postgresql`-tagged block highlights identically to `sql`. Proves R-38, C-05, K-05. |
| **T-06** | `test-docs/code.md`: each of the nine languages is coloured; an unknown fence (` ```brainfuck `) is plain monospace with the label shown; a `bash` block with `$ ` prompts and one output line offers *Copy Without Prompts*; the copy has no prompts, the output line is present, and the line count is unchanged; the same block tagged `console` and `fish` offers it too (plain-highlighted), tagged `shell-session` or `powershell` it does not. Proves R-08, C-05, K-05. |
| **T-07** | `test-docs/math.md`: inline, display, `cases`/`pmatrix`/`aligned`, math in lists/quotes/tables/headings, `\boxed`, registered symbols; the "must NOT become math" section stays literal; the "Errors" section shows source + message. Proves R-12..R-14, C-07, E-07, E-10, E-16. |
| **T-08** | Same file: the TOC shows `Heading with Σ in it` and `π at h2 size, a/b too` (Unicode, no `$`); the `##` heading's π is visibly larger than body π. A heading `## _Draft_ notes` shows in the TOC, and as a ⌘D title, as `Draft notes` (no underscores); `## snake_case_name` keeps its underscores. Proves R-13, R-21, R-27, C-07.3, C-12, I-010. |
| **T-09** | `test-docs/images.md`: relative image renders; missing file shows the named placeholder; a `data:` image renders; an `https:` image shows "Remote image blocked" until View → Load Remote Images, then loads. Proves R-16, E-11. |
| **T-10** | `test-docs/thematic-break.md` and `tables.md` with Smart Typography on: rules and tables render; inline `--flag` and code spans keep straight characters; prose quotes curl. Then switch to Phosphor: the menu item reads "(off for this theme)" and is disabled. Proves R-17, C-10, I-012. |
| **T-11** | Zoom ⌘= five times from $1.0$: body text, headings, inline code, fenced code blocks, and math grow together; the post-change HUD shows 150 %; Actual Size resets to 100 %; relaunch restores the saved factor. Write `1.25` into `mdv_font_scale`, relaunch, then press ⌘=: R-30 rounds $1.25$ to $1.3$, adds $0.1$, stores $1.4$, and the only post-change HUD reads 140 %. Proves R-30, K-04, K-10, C-04, C-05. |
| **T-12** | Choose System theme; toggle macOS appearance: the article switches high-contrast ↔ twilight live. Proves R-29. |

### 9.3 Mermaid (scripted via the harness, then manual)

| ID | Test |
| -- | ---- |
| **T-13** | Run `swift run --package-path tools/render-harness render-harness --scan test-docs/mermaid --output-dir "$TMPDIR/mdv-scan"`: discovery includes every raw `.mmd` file and any Mermaid fence in `.md` files in C-17 order; exit is 0, every E-02 unsupported type is reported `fallback`, every other case is `pass`, and no crash report is created. Repeat with networking disabled; outputs and JSON records are identical. In the app, switch documents while a large diagram is laying out: the new document never shows the old diagram. Proves R-10, R-39, C-17, I-001, I-002, E-01, E-02, E-25. |
| **T-14** | The diagram of E-01 (two subgraphs claiming `PD`) renders with `PD` in the *last* subgraph. Proves C-06.2, E-01. |
| **T-15** | A diagram with front matter, `<b>` labels, `[/parallelogram/]`, `style X fill:#eee` and `fill:white`: renders with clean labels and light-grey/white fills. Proves C-06.1, E-14. |
| **T-16** | `xychart-beta` with `line "a" [...]`: two curves visible. Proves E-15. |
| **T-17** | Run `swift run --package-path tools/render-harness render-harness --check test-docs/render-cases.json --case mermaid-math-ink`: exit is 0; the whole-`$$` node is typeset, mixed and edge labels use C-07.3 Unicode, the label is 16 pt, and the §7.1 ink threshold passes at $2\times$. Proves R-15, R-39, C-17, I-009, K-08. |
| **T-18** | Resize a window across a diagram wider than the column: labels remain sharp, the diagram never exceeds natural width, and ordinary widths equal the §7.2 formula (with `high-contrast` in a window wider than the cap: 732 pt). Force $w_{\mathrm{col}} < 37$ pt: the raster width is exactly 1 pt and no negative or zero size reaches the rasterizer. Proves R-11, I-005, K-07, K-13, §7.2. |
| **T-19** | Run `swift run --package-path tools/render-harness render-harness --check test-docs/render-cases.json --case sequence-layout`: exit is 0; no label crosses a lifeline it does not span or overlaps an arrow/block header, the final note is enclosed, autonumber discs $1,\ldots,n$ appear, and a 3-line row is 30 pt taller than a 1-line row. Proves R-39, C-06.2, C-17, E-13, K-08. |
| **T-20** | A `stateDiagram-v2` with several `ID: line` descriptions and `classDef` colours: each state shows all its lines and its colours. Proves C-06.1 rule 4, C-06.2. |
| **T-21** | Mermaid block controls: style menu switches and persists after relaunch; Show Source toggles; Export PNG writes a file whose pixel size is $2\times$ the natural point size; pinch zoom clamps at $4\times$ and $0.5\times$. Proves R-09, K-07. |

### 9.4 Navigation, find, search, bookmarks (manual)

| ID | Test |
| -- | ---- |
| **T-22** | `test-docs/links.md`: a sibling path navigates in-app and ⌘← returns; same-document `#fragment`, a percent-encoded UTF-8 fragment, and `sibling.md#fragment` reach the first matching C-11 slug, with the cross-file fragment overriding saved scroll position. A missing same-document fragment is a no-op; a missing cross-file fragment loads the file at its top. `https:` opens the browser; a broken local link does not navigate. Duplicate `### Example` headings resolve `#example` to the first and leave `#example-1` unmatched; h4 and setext targets remain unmatched. `#a---b`, `#c--rust`, and `#draft-notes` reach the named GitHub-style headings. A sibling path load and a same-document TOC/fragment jump create back snapshots. A bookmark in another file loads it but ⌘← does not return to the pre-bookmark file. Proves R-18, R-19, R-21, R-27, C-11, C-12, E-05, E-06, E-22. |
| **T-23** | Immediately after ⌘F, the empty query shows "No matches" and disables ⌘G; a whitespace-only non-empty query is matched verbatim. For "the" in one block three times, $m$ rises by three and ⌘G advances $n$ three times while the block stays in view with all three occurrences in the stronger tint. An inline-image paragraph, code fence, and `$$` display block are tinted; ordinary prose is highlighted per character. Query `**` on `**bold**` counts 2 and marks nothing. ⌘G/⇧⌘G wrap; Esc closes. With sidebar focus, ⌘F focuses global search. Proves R-24, E-17, E-18. |
| **T-24** | ⌘⇧F "auth" includes a file containing "authentication" with the term highlighted; choosing it opens the file. "résumé" matches "resume"; an empty or whitespace query returns none. Editing without changing mtime leaves old indexed content; touching then opening by ⌘O re-indexes, while selecting from the sidebar does not. Insert 81 files with identical FTS rank in reverse path order: results are the first 80 by `path COLLATE NOCASE`, then binary path, exactly as C-03; repeated queries return the same sequence. Proves R-01, R-25, R-26, C-03, K-03, K-09, E-24. |
| **T-25** | Open 101 distinct files: the sidebar shows the newest 100, most recent first, no duplicates, and ⌘⇧F for a word unique to the first file finds nothing (evicted from the index); click the third row: it loads and the order is unchanged; ⌘O the same file: it moves to the top. Swipe-delete removes one and ⌘⇧F no longer finds that file, and re-opening it starts at the top (scroll position removed); swipe-delete the **displayed** row: the next row's file loads and ⌘← does not return to the deleted one; with one row left, delete it: the window shows the empty drop target; relaunch preserves the list; the stored `mdv_history` value decodes per C-15. Proves R-01, R-18, R-20, R-26, I-013, K-03, C-15, §3.1. |
| **T-26** | Hover a paragraph and ⌘D: the bookmark anchors there and uses the preceding heading; with no hover it uses the topmost visible block. Duplicate bookmarks create duplicate rows. Beyond the 40-block look-back, the stripped first line is truncated to 60 extended grapheme clusters; an empty stripped line becomes `(line n)`. Insert content above an anchor: fingerprint resolution still lands on it; delete it: the clamped index is used. Delete the file: the row is marked missing and its shortcut beeps. Unit cases verify that tabs, CRLF, NBSP, and repeated spaces normalize to U+0020; non-ASCII case uses locale-independent lowercase; canonically equivalent but byte-distinct combining sequences remain distinct; and truncation counts 80 extended grapheme clusters, including emoji. Proves R-27, C-08, E-08, E-09, K-06, K-09. |
| **T-27** | ⌘⇧0, scroll away, ⌘0 returns; open another file, ⌘0 loads the first file and returns; ⌘0 then ⌘← does not go back to the pre-⌘0 spot; delete the placeholder's file, ⌘0: beep, view unchanged; follow a link to B and delete A, ⌘←: beep, still on B; relaunch: ⌘0 beeps. Proves R-18, R-28, E-27. |
| **T-28** | Scroll to the middle, quit, and relaunch with no argument: the same readable history head is displayed at the same position; modify it externally before relaunch and the document starts at the top. Make the persisted head unreadable while a later row remains readable: launch enters `EMPTY`, retains both rows, and does not try the later row. With empty history, launch enters `EMPTY`. Quit with A as the head, then cold-start with `bin/mdv B.md`: B is displayed without first restoring A, and ⌘← does not show A. Proves R-06, R-18, R-40, C-08, E-03, E-08, K-06, §3.1. |
| **T-29** | With the file open, save it from an editor five times within 50 ms (script): at most two reloads, the final content is displayed, scroll position kept. Save via `mv tmp file` (atomic rename): reloads. `rm file`: content stays, no error; re-create it: reloads. Write invalid UTF-8 over it: content stays; write valid content: reloads. Truncate the file to zero bytes and write it back 100 ms later: no blank frame is shown. Leave it empty for 1 s: the page shows empty. Proves R-05, K-06, E-19, E-21. |
| **T-30** | Single-click a heading: the section flashes and the pasteboard holds its Markdown source ending at the next same-or-higher heading; click again: it flashes again; ⇧-click behaves the same. Drag across a paragraph: text is selected and ⌘C pastes rendered text; dragging on a heading selects nothing. Hover and click a `####` heading: arrow pointer, text selectable, nothing copied. Throughout, the TOC row, find match, and bookmark for one paragraph all address the same block index. Proves R-22, C-12, E-22, I-004. |
| **T-31** | Drag the inspector's left edge to 520 pt and 180 pt (clamps), relaunch: width kept; drag the sidebar divider: clamps at 180/400. Proves R-20, R-21, K-04. |
| **T-42** | Set every C-04 key to a non-default valid value, relaunch, and verify each visible behavior/value is restored. Then, one key at a time, store a wrong type, an out-of-range number, malformed `mdv_history` JSON, and unknown theme/Mermaid ids; relaunch and verify the exact C-04 default or clamp without a crash. Covers smart typography, remote images, sidebar collapse, inspector visibility/width, bookmark expansion/height, editor path, history, theme, font scale, and Mermaid style. Proves R-32 and C-04. |

### 9.5 Robustness and resources (scripted)

| ID | Test |
| -- | ---- |
| **T-32** | On an otherwise idle `macos-15` host, open `test-docs/math.md`, wait 5 s without input, then collect 30 one-second process-CPU samples. Compute the median and nearest-rank 95th percentile over exactly those samples: they are respectively $\leq 1\,\%$ and $\leq 3\,\%$. Proves I-008 and K-15. |
| **T-33** | Corrupt `mdv.db` (truncate the file) and launch: the app opens, documents render, `NSLog` shows the `[mdv]` failure line; bookmarks and search are empty; no crash. Kill the app mid-⌘D (`kill -9` in a loop): on relaunch every bookmark row is either complete or absent. Proves E-12, I-006, I-007. |
| **T-34** | `diff -r` between `Vendor/SwiftMath/Sources` and upstream v1.7.3 `Sources/SwiftMath` shows only the files and hunks listed in `Vendor/SwiftMath/README.md`. Proves I-011. |
| **T-35** | Open a document while the same path is open in a second window, edit it on disk: both windows reload. Proves E-20. |
| **T-40** | With two windows open showing different files, make window 2 key: `open -a build/mdv.app c.md` loads `c.md` into window 2 only; ⌘O shows one open panel; ⌘D adds exactly one bookmark (window 2's); ⌘← navigates window 2 only; ⌘F opens window 2's find bar only. Proves R-01, R-18, E-26. |
| **T-38** | Choose an editor via File → Edit → Choose Editor…, ⌘E: the file opens there; Forget Editor, ⌘E: the chooser appears. ⌘?: Help opens, `~/Library/Application Support/mdv/Help.md` exists, and ⌘D inside it creates a bookmark with that path. Proves R-23, R-31. |
| **T-39** | Fence edge cases (E-23): a ` ```` ` block containing a ` ``` ` line, an unclosed fence at EOF, and an indented code block with a blank line render per C-02. CRLF and LF copies produce the same block count and TOC. An ISO-8859-1 file does not open, keeps the previous document, and adds no row; a zero-byte `.md` opens as an empty article. With find open on "the", save one additional occurrence: $m$ rises by one and the bar reads "$1$ of $m$". Proves R-04, R-24, C-02, E-03, E-23. |
| **T-36** | Grep the built binary's log output during T-05..T-31 (`log stream --process mdv`): no line contains document text, a query string, or a path, except the `[mdv]` failure message and lines beginning `"mathFonts bundle resource:` (the SwiftMath font-registration lines R-35 permits). Proves R-35, I-003. |
| **T-41** | Generate each K-14 payload at the exact ceiling and one unit above it. Exact-ceiling inputs reach their normal renderer; oversized document, Mermaid, LaTeX, compressed image, decoded-pixel, decoded-byte, and image-axis cases produce the E-28 outcome without a crash or parser/decode invocation. With a local recording HTTP server, remote loading off sends no request; on sends only unauthenticated `GET` with no Cookie/Authorization/Referer, follows five `http(s)` redirects but rejects the sixth or a non-HTTP target, fails at 15 s connection or 30 s resource timeout, cancels above 32 MiB, persists no body, and cancels when the preference turns off. Proves R-16, R-36, R-41, C-16, I-001..I-003, K-14, E-11, E-28. |

## 10. Dependencies and environment

| Dependency | Version / pin | Role |
| ---------- | ------------- | ---- |
| macOS | $\geq$ 13.0 (built and tested on 15) | platform |
| Swift toolchain | $\geq$ 5.9 (`swift-tools-version: 5.9`); CI uses the `macos-15` runner's Xcode | build |
| `gonzalezreal/swift-markdown-ui` | from 2.0.2, resolved 2.4.1 | GFM → SwiftUI; image-provider and code-highlighter hooks |
| `swiftlang/swift-cmark`, `gonzalezreal/NetworkImage` | transitive | cmark-gfm; default remote image loader |
| `ChimeHQ/SwiftTreeSitter` | from 0.8.0, resolved 0.25.0 (`tree-sitter` 0.25.10) | tree-sitter runtime |
| tree-sitter grammars (9) | commits in `mdv/Grammars/README.md`, vendored C sources compiled as target `CGrammars` | code highlighting |
| `lukilabs/beautiful-mermaid-swift` | from 1.0.4 (`elk-swift` 1.0.2) | Mermaid parse/layout/render |
| SwiftMath (`mgriebling/SwiftMath` 1.7.3) | **vendored** at `Vendor/SwiftMath` with the patches listed in its `README.md` (font-bundle resolution, public `MTMathAtom.init`, `\boxed`, trimmed font bundle) | LaTeX typesetting; font `latinmodern-math.otf` (GUST licence) |
| SQLite | system `libsqlite3` (linked via `linkerSettings`), FTS5 | persistence |
| Fonts | Alegreya, Besley, OpenDyslexic (`mdv/Fonts`, registered at launch) | themes |
| Release tooling | `codesign`, `notarytool` (keychain profile), `stapler`, `spctl`, `gh` | `make dist`, `github-release` |

Environment variables: `MDV_APP` (launcher bundle override); release-time Makefile inputs per §5.3. Runtime files: `~/Library/Application Support/mdv/{mdv.db, Help.md}`, `UserDefaults` domain `com.mdv.app`. Install and run: `make install`; run tests: there is no suite yet (R-37) — execute §9 manually, or run the exact C-17 `swift run --package-path tools/render-harness render-harness …` commands once R-39 lands.

## 11. Traceability matrix (id → where realized)

Statuses: a plain row is realised and verified as written; *not yet realised* marks specified work with no implementation; **open defect** marks a known code violation; *verification pending* marks an implemented path whose revised behavior has not yet been observed. At v0.8, R-37..R-39, R-41, C-16/C-17, K-14, and E-28 are not yet realised; R-16, R-19, R-34, R-36, C-03, I-001..I-003, and E-11 have open defects introduced or exposed by F-079..F-081, F-086, and F-088; R-40, C-08, and K-15 await verification. All other F-076..F-093 changes are specification/test corrections or match the previously traced behavior.

| Spec id | Where realized | Verified by |
| ------- | -------------- | ----------- |
| R-01 | `mdvApp.swift`, `ContentView.loadFile/select`, addressed notifications | T-03, T-04, T-22, T-24, T-26, T-40 |
| R-02 | `ContentView.loadDirectory` | T-04 |
| R-03 | `ContentView.handleDrop` | T-04 |
| R-04 | `ParsedDocument`, `ContentView.readDocument/loadCurrentEntry` | T-30, T-39 |
| R-05 | `FileWatcher`, `ContentView` watcher hookup | T-29 |
| R-06 | `persistScrollPosition`, `Database.scroll_positions` | T-28 |
| R-07 | MarkdownUI via `ThemeManager.markdownTheme` | T-05 |
| R-08 | `CodeRenderer`, `CodeBlockChrome` | T-06 |
| R-09 | `MermaidCodeBlockChrome`, `MDVMermaidDiagramView` | T-21 |
| R-10 | `MDVMermaidPipeline`, `MermaidFallbackView` | T-13, T-15 |
| R-11 | `MDVMermaidDiagramView.displayWidth`, raster cache | T-18 |
| R-12 | `MathMarkdown`, math image providers/views | T-07 |
| R-13 | heading math scales, `MDVTheme.headingSizeEms` | T-08, T-11 |
| R-14 | `MathImageCache`, `MathSymbols` | T-07 |
| R-15 | Mermaid math substitution/raster composition | T-17 |
| R-16 | **open defect F-079/F-080** — existing providers lack C-16/K-14 | T-09, T-41 |
| R-17 | `smartenMarkdown`, `ContentView.blockView` ordering | T-10 |
| R-18 | per-window stacks, snapshot push/apply/drop paths | T-22, T-25, T-27, T-28, T-40 |
| R-19 | **open defect F-086** — path-plus-fragment contract incomplete | T-22 |
| R-20 | `HistoryManager`, sidebar views | T-25, T-31 |
| R-21 | inspector, TOC parsing/views | T-08, T-31 |
| R-22 | selection, `copySection`, heading interaction | T-30 |
| R-23 | editor picker and launcher | T-38 |
| R-24 | find state, match counting/highlighting/routing | T-23, T-39 |
| R-25 | `Database.search`, global-search UI | T-24 |
| R-26 | index/reindex/prune/remove lifecycle | T-24, T-25 |
| R-27 | `BookmarksManager`, title/anchor/menu paths | T-22, T-26 |
| R-28 | placeholder set/jump paths | T-27 |
| R-29 | `ThemeManager`, toolbar picker | T-12, T-42 |
| R-30 | font-scale step/HUD and scaled renderers | T-11, T-42 |
| R-31 | `HelpManager.openHelp` | T-38 |
| R-32 | C-04 `@AppStorage` keys | T-42 |
| R-33 | `bin/mdv` | T-03 |
| R-34 | **open defect F-081** — `VERSION` can bypass exact-tag derivation | T-01, T-02, T-43 |
| R-35 | diagnostic call sites and absence of content logging | T-36 |
| R-36 | **open defect F-080** — K-14/E-28 preflight absent | T-13, T-41 |
| R-37 | *not yet realised* — automated test target and CI step | future `swift test` CI |
| R-38 | *not yet realised* — vendored Swift/SQL grammars | T-37 |
| R-39 | *not yet realised* — C-17 harness, corpus, manifest | T-13, T-17, T-19 |
| R-40 | *verification pending F-076/F-077* — revised startup paths | T-28 |
| R-41 | *not yet realised* — preflight ceilings and rejection paths | T-41 |
| C-01 | `Info.plist`, entitlements, `build.sh` | T-01 |
| C-02 | `ParsedDocument.parseBlocks/parseTOC` | T-07, T-30, T-39 |
| C-03 | **open defect F-088** — search query lacks path tie-breaks | T-24 |
| C-04 | `@AppStorage` declarations and invalid-value fallbacks | T-11, T-42 |
| C-05 | language resolution, highlighting, code cache | T-06, T-11 |
| C-06 | `MDVMermaidPipeline`, diagram theme/repairs | T-13..T-20 |
| C-07 | `MathSpec`, `MathMarkdown`, `MathSymbols`, `MathImageCache` | T-07, T-08, T-17 |
| C-08 | *verification pending F-087* — fingerprint/anchor implementation | T-26, T-28 |
| C-09 | `MDVTheme`, `ThemeManager.markdownTheme` | T-08, T-10, T-12 |
| C-10 | `SmartTypography.swift` | T-10 |
| C-11 | `headingSlug` | T-22 |
| C-12 | `sectionRange`, `copySection`, `stripInlineMarkdown` | T-08, T-22, T-30 |
| C-13 | `build.sh` | T-01 |
| C-14 | fallback views, placeholders, beeps, alerts | T-07, T-09, T-13, T-26, T-38, T-41 |
| C-15 | `HistoryEntry`, `HistoryManager.save/load` | T-25 |
| C-16 | *not yet realised* — isolated remote-image session | T-41 |
| C-17 | *not yet realised* — render harness and manifest | T-13, T-17, T-19 |
| I-001 | **open defect F-079/F-080** until C-16/K-14 land | T-09, T-13, T-41 |
| I-002 | **open defect F-080** until K-14/E-28 land | T-13, T-41 |
| I-003 | **open defect F-079** until C-16 isolates URL disclosure | T-36, T-41 |
| I-004 | cached `ParsedDocument` block split | T-30 |
| I-005 | shared display/raster size function | T-18 |
| I-006 | `Database` connection flags/pragmas | T-33 |
| I-007 | whole-row/upsert persistence writes | T-33 |
| I-008 | bitmap-backed math rendering | T-32 |
| I-009 | pixel-snapped Mermaid math and §7.1 metric | T-17 |
| I-010 | `TOCHeading.slugText` and heading math handling | T-08, T-22 |
| I-011 | `Vendor/SwiftMath/README.md` patch inventory | T-34 |
| I-012 | smart-typography exclusions and ordering | T-10 |
| I-013 | `HistoryManager.add/select` ordering | T-25 |
| K-01 | `Package.swift`, `Info.plist`, build checks | T-01 |
| K-02 | `Info.plist`, entitlements, bundle build | T-01 |
| K-03 | history/search/bookmark limits | T-24, T-25, T-26 |
| K-04 | font and panel clamps | T-11, T-31 |
| K-05 | `CGrammars`, supported-language table | T-06, T-37 |
| K-06 | watcher/timer/mtime/title constants | T-26, T-28, T-29, T-30 |
| K-07 | Mermaid view/cache and §7.2 formula | T-18, T-21 |
| K-08 | Mermaid/math layout constants | T-17, T-19 |
| K-09 | fingerprint and FTS tokenizer | T-24, T-26 |
| K-10 | `MDVTheme` defaults | T-11 |
| K-11 | `Makefile dist` chain | T-02, T-43 |
| K-12 | `build.sh` codesign and bundle placement | T-01 |
| K-13 | padded article-frame layout | T-18 |
| K-14 | *not yet realised* — byte/dimension ceilings | T-41 |
| K-15 | *verification pending F-091* — idle benchmark | T-32 |
| E-01 | subgraph ownership normalization | T-14 |
| E-02 | unsupported-diagram fallback | T-13 |
| E-03 | read/decode guards and startup path | T-04, T-28, T-39 |
| E-04 | empty-directory path | T-04 |
| E-05 | broken local-link handling | T-22 |
| E-06 | **open defect F-086** — fragment failure variants incomplete | T-22 |
| E-07 | math delimiter recognition | T-07 |
| E-08 | anchor resolution/scroll validity | T-26, T-28 |
| E-09 | missing-bookmark handling | T-26 |
| E-10 | math fallback | T-07 |
| E-11 | **open defect F-079/F-080** — C-16 failure semantics absent | T-09, T-41 |
| E-12 | database error paths | T-33 |
| E-13 | sequence-label spacing repairs | T-19 |
| E-14 | Mermaid colour normalization | T-15 |
| E-15 | xychart sanitization | T-16 |
| E-16 | image-only math placement | T-07 |
| E-17 | find tint/highlight exclusions | T-23 |
| E-18 | sidebar-focused find routing | T-23 |
| E-19 | reload selection behavior | T-29 |
| E-20 | independent per-window watchers | T-35 |
| E-21 | delete/transient-read watcher behavior | T-29 |
| E-22 | non-TOC heading behavior | T-22, T-30 |
| E-23 | fence/splitter deviations | T-39 |
| E-24 | empty global search | T-24 |
| E-25 | stale render cancellation | T-13 |
| E-26 | key-window routing | T-40 |
| E-27 | missing snapshot/placeholder targets | T-27 |
| E-28 | *not yet realised* — over-limit rejection/fallback | T-41 |

## 12. Open questions and decisions to confirm

| ID | Decision | Default taken | Alternatives | Affects | Owner / status |
| -- | -------- | ------------- | ------------ | ------- | -------------- |
| D-01 | No automated test suite exists today; the product MUST have one. | R-37 added; §9.0 names the target groups and which manual tests migrate to each; the app SHOULD be split into `mdvCore` (library) + executable so tests can `@testable import` it; the harness and diagram corpus move into the repository (R-39). | Keep manual-only; or XCUITest-only. | R-37, §9, R-36 | owner / **confirmed v0.1** (2026-09-14) |
| D-02 | Inline math with descenders sits `descent` points above the baseline (SwiftUI `Text(Image)` has no baseline hook through MarkdownUI). | Accepted as a known limitation; documented in `NOTES.md`. | Fork or vendor MarkdownUI to apply `.baselineOffset` in `TextInlineRenderer.renderImage` (one-line patch). | R-12 | maintainer / **confirm** |
| D-03 | SwiftMath is vendored (not a package dependency) because of the resource-bundle/codesign conflict. | Vendored with four patches, one font. | Fork on GitHub and depend on the fork; ship more math fonts and expose a font choice. | C-07, I-011, K-12 | maintainer / **confirm** |
| D-04 | Mermaid diagram types the library lacks (`timeline`, `gantt`, `pie`, `mindmap`, `gitGraph`, `journey`, `quadrantChart`) show the fallback. | Fallback only. | Implement the simpler ones (`pie`, `timeline`) in mdv on top of the library's renderer primitives; or switch library. | R-10, E-02 | maintainer / open |
| D-05 | Sequence diagrams do not mirror actor boxes at the bottom, and message labels use the library's muted grey rather than Mermaid's black. | Library defaults kept. | Draw mirrored actors in `rasterize`; override the label colour to foreground. | C-06.2 | maintainer / **confirm** |
| D-06 | xychart series names are dropped (legend reads `Line n`) and front-matter `themeCSS` (dash patterns, widths) is discarded. | Accept. | Draw the legend in mdv from the names captured in `sanitize`. | E-15 | maintainer / **confirm** |
| D-07 | Parallelogram nodes render as rectangles (library has no such shape). | Rectangle. | Draw the slanted shape in mdv after rendering (node rects are known). | C-06.1 rule 5 | maintainer / **confirm** |
| D-08 | State-diagram descriptions render as a single multi-line label rather than Mermaid's title compartment + divider. | Single label. | Draw the divider line in mdv under the first line. | C-06.1 rule 4 | maintainer / **confirm** |
| D-09 | Document-style Mermaid node fills use the page colour (25 % toward the code background) on light themes. | As stated. | Keep the previous grey (6 % toward foreground); make it a per-theme field. | C-06.3 | maintainer / **confirm** |
| D-10 | History sidebar width is not persisted (inspector width is). | Not persisted. | Persist under `mdv_sidebar_width` for symmetry. | R-20, C-04 | maintainer / **confirm** |
| D-11 | The `.txt` and `.mkd` extensions are accepted for drag-and-drop but not for link navigation or directory scans. | As built. | Unify the extension sets (C-02 uses `md/markdown/mdown`, drop uses five). | R-02, R-03, R-19 | maintainer / **confirm** |
| D-12 | The CLI symlink installed by `make install` points into the checkout (`bin/mdv`), while the in-app installer points at `Contents/Resources/mdv`. | Two install paths coexist. | Make `make install-cli` link to the bundled copy too. | R-33, R-34 | maintainer / **confirm** |
| D-13 | Bundle version is fixed at `1.0.0` in `Info.plist` while releases are versioned by git tag. | Tag governs the artefact name only. | Stamp `CFBundleShortVersionString` from the tag in `build.sh release`. | K-02, K-11 | maintainer / **confirm** |
| D-14 | "Load Remote Images" is off by default (privacy). | Off. | On by default like most viewers. | R-16 | product / confirmed by README intent |
| D-15 | Which SQL grammar backs R-38. | `DerekStride/tree-sitter-sql` (dialect-agnostic, actively maintained, ships `highlights.scm`); Swift from `alex-pinkus/tree-sitter-swift` (its `parser.c` is generated — vendor the generated `src/`, ~10 MB, not `grammar.js`). | `m-novikov/tree-sitter-sql` (PostgreSQL-only); per-dialect grammars. | R-38, K-05 | maintainer / **confirm** |
| D-16 | Files that are not valid UTF-8 (Latin-1 / Windows-1252 Markdown) are refused silently (E-03). | Strict UTF-8, load aborted, window unchanged. | Decode with U+FFFD replacement; try UTF-8 then ISO-8859-1; show an "unreadable" notice in place. | R-04, E-03, T-39 | maintainer / **confirm** |
| D-17 | Fragment targets are only `#`–`###` single-line ATX headings, and duplicate slugs resolve to the first heading (no GitHub `-1` suffixes). | As built (E-22, C-11). | Collect h4–h6 and setext headings for slug purposes; generate GitHub's numeric suffixes. | R-19, R-21, C-02, C-11, E-22 | maintainer / **confirm** |
| D-18 | How a reload treats an empty or undecodable file read mid-save. | A failed/undecodable read is ignored (page kept until a later readable event); a zero-byte read is re-read after 500 ms and that read is shown (R-05, E-21). | Always show what was read (as built — blanks the page); never show empty; make the window configurable. | R-05, E-21, T-29 | maintainer / **confirm** |
| D-19 | Multi-window command and open-event routing (R-01, E-26, T-40). | Requirement kept: only the key window acts; fixed in code at v0.7 (F-042): the target `NSWindow` rides in each notification's `userInfo`, `NotificationHandlers` ignores notifications not addressed to its window, and `application(_:open:)` targets `NSApp.keyWindow`. | Declare mdv single-window: drop ⌘⇧O, or document that every window reacts to every command. | R-01, R-18, R-24, R-27, §5.1, E-20, E-26 | maintainer / **confirm** |
| D-20 | Heading-slug hyphen rule (C-11): GitHub-compatible or as built. | GitHub-compatible (every whitespace run → `-`); fixed in code at v0.7 (F-052). | Keep the as-built rule and document it precisely ("a whitespace run after a `-` emits nothing"). | C-11, I-010, R-19, T-22 | maintainer / **confirm** |
| D-21 | Find: whether the current occurrence is visually distinguished within a block, and whether `$$` blocks are tinted (R-24, E-17). | Current occurrence not distinguished (as built, documented); `$$` blocks tinted (requirement; fixed in code at v0.7, F-048). | Store the source range in `SearchMatch` and mark the current occurrence; or leave `$$` blocks inline-highlighted and document it. | R-24, E-17, T-23 | maintainer / **confirm** |
| D-22 | `migrate()` transactionality (§3.3). | Requirement kept (one transaction per migration incl. the bump); fixed in code at v0.7 (F-051). | Reword §3.3 to the as-built idempotent-statement rule. | §3.3, I-007, T-33 | maintainer / **confirm** |
| D-23 | Undecodable or vanished file, and what an empty file displays (R-04, E-03). | Requirement kept: decode before the history change, abort on failure, previous document kept; an empty file shows an empty article with its row selected; fixed in code at v0.7 (F-062). | Document the as-built behaviour (empty panel, row added); or decode with U+FFFD replacement (see D-16). | R-04, E-03, §3.1, T-39, T-27 | maintainer / **confirm** |
| D-24 | Adding vs. selecting routes (R-01), and snapshots whose row was removed (R-18). | Routes split as built: sidebar row, search hit, ⌘←/⌘→ and delete-current-row neither reorder history nor re-index. Snapshots of a removed row MUST be dropped; fixed in code at v0.7 (F-063). | Route every selection through `history.add` (sidebar reorders on click, re-indexes on every selection); or let ⌘← re-add the row. | R-01, R-18, R-20, R-26, §3.1, T-24, T-25 | maintainer / **confirm** |
| D-25 | Index rows for files evicted by the 100-entry cap (R-26). | Requirement kept: prune on eviction and at launch; fixed in code at v0.7 (F-064). | Narrow R-26 to swipe-delete only and accept orphan rows. | R-26, I-013, K-03, T-25 | maintainer / **confirm** |
| D-26 | Whether fenced code blocks follow the zoom factor (R-30). | They MUST (fence text $= 0.85 \times$ base $\times$ scale); fixed in code at v0.7 (F-065). | Exempt fences (fixed at $0.85 \times$ base) and say so in R-30/T-11. | R-30, C-05, T-11 | maintainer / **confirm** |
| D-27 | Placeholder or snapshot whose file is missing (E-27). | Beep and no navigation, as E-09; fixed in code at v0.7 (F-074). | Document the as-built silent no-op for ⌘0. | R-28, R-18, E-27, T-27 | maintainer / **confirm** |
| D-28 | Initial history head is unreadable at launch (F-076). | Attempt only the head, retain it, enter `EMPTY`, and do not scan later rows. | Remove the head; scan to first readable row; show an error page. | R-40, §3.1, E-03, T-28 | maintainer / **confirm** |
| D-29 | Cold-start file argument and unseen restored history (F-077). | The argument pre-empts restoration and creates no snapshot for the unseen head. | Restore the head first and make it reachable with ⌘←. | R-18, R-40, T-28 | maintainer / **confirm** |
| D-30 | Cross-file bookmark and placeholder snapshot policy (F-078). | Neither route pushes, regardless of whether it changes files. | Push on every file change; push bookmarks but not placeholders. | R-18, R-27, R-28, T-22, T-27 | maintainer / **confirm** |
| D-31 | Remote-image disclosure and resource ceilings (F-079, F-080). | Isolated unauthenticated session per C-16; fixed K-14 byte/dimension ceilings; visible E-11/E-28 fallback. | Use shared URL loading; permit cookies; rely on available memory; make limits configurable. | R-16, R-36, R-41, C-16, I-001..I-003, K-14, E-11, E-28, T-41 | maintainer / **confirm** |
| D-32 | Can `VERSION` bypass exact-tag release provenance (F-081)? | No; every `dist` derives the version only from the exact tag. | Keep the override; add a separate non-release packaging target. | R-34, §5.3, K-11, T-02, T-43 | maintainer / **confirm** |
| D-33 | Render-harness CLI, corpus discovery, and comparison tolerance (F-082). | C-17 commands; raw `.mmd` plus Markdown fences; deterministic manifest; channel threshold 8 and mismatch fraction $q \leq 0.001$. | Raw files only; exact PNG equality; platform-specific goldens without tolerance. | R-39, C-17, T-13, T-17, T-19 | maintainer / **confirm** |
| D-34 | Local path plus fragment semantics (F-086). | Percent-decode once, load the file, suppress saved-scroll restoration, then match the first slug; unmatched remains at top. | Restore saved position; ignore cross-file fragments; hand them to the system. | R-19, E-06, T-22 | maintainer / **confirm** |
| D-35 | Durable anchor normalization (F-087). | Unicode-whitespace split, U+0020 join, locale-independent lowercase without normalization, first 80 grapheme clusters. | ASCII whitespace; NFC normalization; UTF-8 byte truncation. | C-08, K-09, T-26 | maintainer / **confirm** |
| D-36 | Equal-rank search order (F-088). | Rank, then case-insensitive path, then binary path. | Rank only; filename; history order. | C-03, R-25, T-24 | maintainer / **confirm** |
| D-37 | Zoom tie rounding (F-090). | Round the current factor to one decimal, half away from zero, then apply the step; HUD shows only the result. | Add then round; ties-to-even; show a pre-change HUD. | R-30, C-04, T-11 | maintainer / **confirm** |
| D-38 | Idle CPU acceptance metric (F-091). | K-15: 5 s warm-up, 30 one-second samples, median $\leq 1\,\%$, nearest-rank p95 $\leq 3\,\%$. | Structural bitmap-only check; mean only; no numeric threshold. | I-008, K-15, T-32 | maintainer / **confirm** |
| D-39 | Empty in-document find (F-085). | No matches and stepping disabled; whitespace-only non-empty input remains verbatim. | Treat empty as every boundary; trim all input. | R-24, T-23 | maintainer / **confirm** |

---

*Revision history*

- *v0.8 (2026-09-14): fifth review applied in full (F-076..F-093). P0: startup-head and cold-argument state fixed (R-40/§3.1/E-03/T-28); bookmark/placeholder exceptions ordered in R-18; C-16/K-14/E-28/T-41 define remote disclosure and resource exhaustion; exact-tag release gate and positive release test added; C-17 pins the render harness, corpus, manifest, exits, and pixel metric. P1: I-013 recency, 1 pt raster bound, empty find, cross-file fragments, Unicode fingerprints, FTS tie order, complete preference test, zoom rounding, and CPU protocol pinned. P2: E-21 self-transition and math notation corrected. R-37..R-39/R-41 remain not realised; newly exposed implementation gaps are marked in §11. D-28..D-39 record the defaults awaiting confirmation.*
- *v0.7 (2026-09-14): all ten *open defects* fixed in the code, in the same commit as this revision — F-042 (commands and open events addressed to the key window), F-045 (`_…_` stripping), F-048 (`$$` fences tinted in find), F-051 (`migrate()` in one transaction with rollback), F-052 (GitHub whitespace-run slug rule), F-062 (decode before any history/selection change; `EMPTY` keyed on the selection), F-063 (snapshots of removed rows dropped/skipped), F-064 (index pruned on eviction and at launch), F-065 (fenced code follows the zoom factor; cache key), F-074 (⌘0/⌘←/⌘→ to a missing file beep). Markers removed from R-01, R-04, R-18, R-24, R-26, R-30, §3.1, §3.3, C-05, C-11, C-12, E-03, E-17, E-26, E-27, T-11, T-23, T-25, T-27, T-39, T-40 and §11; D-19..D-27 record the fix. No ids renumbered.*
- *v0.6 (2026-09-14): fourth review applied (F-062..F-075). P0: R-04/E-03 decode-before-add and the empty-file rule, *open defect* (F-062, D-23); R-01 split into adding and selecting routes, §3.1 `LOADING` row split, R-20/R-26 reworded to "added", R-18 snapshot-drop rule *open defect* (F-063, D-24). P1: R-26 eviction/launch prune *open defect* (F-064, D-25); R-30/C-05 fence zoom *open defect* (F-065, D-26); C-05 prompt-aware fence set (F-066); §7.2 column-width formula, K-13/K-10/T-18 (F-067); C-07.1 host rule, K-08, E-16 (F-068). P2: R-26 scroll-position removal (F-069); C-04 invalid-value paragraph, K-06 index gate (F-070); R-24 reload/verbatim clause (F-071); §5.3 release inputs (F-072); §5.2 launcher edge rows (F-073); E-27 and D-27 (F-074); front-matter commit, §3.3 "clear", §11 R-40 citation, C-06.1 rule 3, C-07.2 `\operatorname`, C-12 "TOC heading" (F-075). New ids: E-27, §7.2, D-23..D-27. No ids renumbered.*
- *v0.5 (2026-09-14): third review applied (F-042..F-061). P0: R-40 (launch restores the history head) and the §3.1 `EMPTY`/`LOADING` entries (F-043); key-window routing kept as the requirement, E-26/T-40 added, R-01 marked *open defect* (F-042, D-19). P1: R-27 title rule (F-044); C-12 `_…_` rule, *open defect* (F-045); C-14 narrowed to document-content failures, §5.1 CLI-install row (F-046); R-24/E-17 restated — count on source, highlight on rendered text, tint-by-exclusion, `$$` clause *open defect* (F-047, F-048, D-21); R-18 snapshot policy and R-28 placeholder anchor (F-049); §3.1 delete-row transitions, R-26 (F-050); §3.3 migration transaction *open defect* (F-051, D-22); C-11 GitHub hyphen rule *open defect* (F-052, D-20); R-01 multi-URL and R-03 first-item rules (F-053); R-22 "TOC heading block" and E-22 (F-054). P2: §5.1 enabled/beep cells (F-055); R-35 log inventory (F-056); R-05/E-21/K-06 `NoDefer` and transient wording (F-057); R-31/§3.3 Help overwrite (F-058); front matter, §10, C-01, §1, §5.3 drift (F-059); R-02 collation and R-26 "added to history" (F-060); C-15 moved after C-13, D-17/D-18 order, revision order, `$\leq$` (F-061). No ids renumbered.*
- *v0.4 (2026-09-14): F-033 (CRLF block splitting) and F-034 (reload on a failed/transient read) fixed in the code; their *open defect* markers removed from C-02, E-21, R-05, T-29, T-39 and §11.*
- *v0.3 (2026-09-14): second review applied (F-032..F-041). P0: R-22 rewritten to the as-built heading-click model — the block-selection model it described was removed in `c50817a`; its traces purged from R-05, §3.1, §5.1, E-19, I-004, T-30, §11. P1: *open defect* status introduced in the front matter and §11 (F-036) and applied to the CRLF line-ending rule (C-02 rule 6, F-033) and the delete/transient reload rule (R-05/E-21, F-034); transient-state rule and D-18 (F-037). P2: K-13 drag handles, blank line before §3, §9.0 wording, rule citations by name (F-038..F-041). No ids renumbered.*
- *v0.2 (2026-09-14): all findings of `SPEC_REVIEW_REPORT.md` applied. P0: F-001 (lifecycle vs E-03). P1: F-002 (*Copy Without Prompts* output), F-003 (path-based watcher, E-21), F-004 (bookmark anchor and title), F-005..F-008, F-010..F-012, F-015 (interaction rules made explicit), F-009 (C-15 history JSON), F-016 (R-39 harness + corpus in-repo), F-017 (§7.1 ink metric). P2: F-013 (E-22, D-17), F-014 (colour list enumerated), F-018 (D-16), F-019 (C-02 rules 2–4, E-23), F-020..F-031 (editorial, notation, K-13 column width, E-24, E-25, T-38, T-39). No ids renumbered.*
- *v0.1 (2026-09-14): first as-built draft, covering the tree at `a6feb14`; §3.2 diagram made vertical; R-37 and §9.0 added after D-01 was confirmed (automated suite is a product requirement); R-38 (Swift and SQL highlighting) and D-15 added.*
