# mdv help

A "totally solved problem in computer science" rendered into a window. Here is what it does and how to make it do it.

## Opening files

- **⌘O** opens a file. **⌘⇧O** opens one in a new window.
- **⌘W** closes the current file — it drops out of history and the next one takes its place. **⌘⇧W** closes the window instead. **⌘⌥W** closes everything and empties the sidebar; it asks first, because it also throws away the search index.
- Drop a `.md` (or `.markdown`, or `.mdown`) onto the icon — works.
- Drop a *directory* onto the icon — picks `README.md` if it finds one, otherwise the alphabetically-first markdown, and seeds the rest into history as siblings.
- Run `mdv FILE` from the terminal once you have installed the CLI. Hit **mdv → Install Command Line Tool…** to drop the symlink into `/usr/local/bin`. Yes, it asks for your password. No, it is not phoning home.

## Moving around

- **⌘←** / **⌘→** — back and forward through files you have recently opened. Like a browser. The thing browsers do.
- **⌘⇧]** / **⌘⇧[** — next and previous file, straight down and up the history sidebar, stopping at the ends. **⌃⇥** / **⌃⇧⇥** do the same thing, for fingers that already know that one.
- Click a link to a sibling `.md` in the same directory — it loads. Click an `https://` link — it goes to your browser, where it belongs.
- `#fragment` links scroll to the matching heading. `[See above](#earlier-section)` actually does that.
- **↓** / **↑** scroll a few lines. **Page Down** / **Page Up** and **space** / **⇧space** go a screen at a time. **Home** / **End** go to the top and the bottom. They work whether or not you have clicked into the text first, which is the entire point.
- Come back to a file and you are where you left off. The scroll position is saved per file and checked against the file's modification time, so a file that changed under you opens at the top instead of somewhere random.

## Find

- **⌘F** — find in the current document. The inline kind, with highlights and a counter, like every text app shipped after 1998.
- **⌘⇧F** — search across every file in your history. This is **TEXT SEARCH TECHNOLOGY**, which other Markdown viewers on the App Store somehow do not ship. Patent pending.

## Bookmarks

Every program eventually evolves bookmarks. We did not fight it.

- **⌘D** — bookmark the spot you are looking at.
- **⌘1**..**⌘5** — jump to bookmark slots 1 through 5.
- **⌘⇧0** — drop a transient placeholder at the current spot. **⌘0** — jump back to it. The placeholder lives in memory only; restart the app and it is gone. That is a feature.
- This help file lives at `~/Library/Application Support/mdv/Help.md`, which means you can bookmark sections of it like anything else. Welcome to the meta-help.

## Sidebars

- **TOC** — h1/h2/h3 headings, click to jump. Toggle from the toolbar; drag its left edge to resize (the width is remembered).
- **History** — every file you have opened, ever, until you swipe one left and tap delete. Survives restart.

## Rendered Markdown

- Tables are tables. Task lists are checkboxes. Headings get heading type.
  This is the boring part and it works.
- Code blocks are highlighted by tree-sitter: bash, C, Go, JavaScript, Python,
  Ruby, Rust, TOML, YAML. Hover one for wrap and copy; right-click for the
  same, plus **Copy Without Prompts** on shell blocks that have prompts in
  them.
- `diff` blocks tint the added and removed lines instead of pretending a diff
  is a syntax.
- Images beside the document load from the document's own directory. `data:`
  URIs work. `http(s)` images are blocked by default and render as a
  clickable placeholder — click it and the View menu opens under your cursor
  at **Load Remote Images**.

## Frontmatter

- A YAML (`---`) or TOML (`+++`) metadata header is metadata, not prose, so it
  does not render as prose: you get a properties table above the document.
- **View → Show Frontmatter** hides the header instead, if you would rather
  see the file exactly as it is on disk. The setting persists.

## Diagrams and math

- `` ```mermaid `` fences render as diagrams. Hover for the toolbar: switch style, show the source, export a PNG.
- Flowcharts, sequence diagrams, class diagrams, ER diagrams, state diagrams, and XY charts render natively. Gantt charts and other diagram types render via a bundled mermaid.js — same toolbar, slightly slower first load.
- `$…$` renders inline LaTeX math and `$$…$$` renders a display equation, typeset natively in Latin Modern Math. Right-click a display equation to copy its LaTeX. `\$` and dollars in code stay dollars; "$5 and $10" stays prose.

## Printing

**⌘P** prints the document through the ordinary macOS print panel, whose **PDF** dropdown is also Save as PDF. That is the entire PDF feature.

- Text prints as text — vector glyphs, not a screenshot of your window.
- LaTeX prints as typeset math. Mermaid diagrams print as diagrams. A diagram that fails to render prints as its source rather than as an empty box.
- Page breaks land in the gaps between blocks, instead of through the middle of a line of text.
- Printed type comes out smaller than screen type, on purpose: the app sets 16pt against its 860pt reading column, and a Letter page only leaves 504pt after margins, so the page is set at about 9½pt. That keeps a printed line about as long as a line in the window — the same words per line, the same paragraphs breaking in the same places. Zoom does not change it.

## Themes and preferences

A frustrated, untalented graphic designer (the author) could not resist letting two LLMs argue with him about typography. The result is several themes. Pick one from the toolbar. Do not @ me about font choices.

- **⌘=** / **⌘-** zoom the document's type — body, headings, code, math. **View → Actual Size** puts it back. Zoom is a reading preference: it does not change what prints.
- **View → Smart Typography** — the curly quotes, em dashes and ellipses pass. Some themes opt out; when the current one does, the menu item says so and greys out.
- **View → Load Remote Images** — the `http(s)` image opt-in. Off by default, because a viewer should not fetch arbitrary URLs on your behalf without being asked.

## Editor integration

- **⌘E** — open the current file in your external editor.
- **File → Edit → Choose Editor…** — pick which editor. **Forget Editor** clears it.

## When things go sideways

If links do not go where you expect, fragments do not scroll, or the CLI complains it cannot find `mdv.app`: file an issue. Or yell at the author about zoning reform. Either works.
