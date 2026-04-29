# Typography Decisions

Tracks per-theme type-style work. Every theme gets a row in the **Catalog** table; the **Conventions** section captures rules that apply across themes.

## Conventions

These are the constants we hold across themes unless a theme explicitly overrides them. Most live as fields on `MDVTheme` in `mdv/ThemeManager.swift`.

| Field | Default | Why |
| --- | --- | --- |
| `bodyFontFamily` | `.system()` | Inherit SF Pro on macOS. Set to `.custom("…")` on themes that bundle a face. |
| `baseFontSize` | `16pt` | Matches `Theme.gitHub`'s body size. macOS apps generally read body at 13pt; we run a touch larger because long-form prose is the main use case. |
| `paragraphLineSpacingEm` | `0.25` | Adds 25% of font size on top of natural line height (~1.2×) → roughly 1.45× total. Reading-tuned themes push to 0.45–0.55. |
| `articleHorizontalPadding` | `34pt` | Default left/right gutter when the column isn't max-width-constrained. |
| `articleMaxWidth` | `nil` | If set, the article is capped at this width and centered. Reading themes use this; UI-density themes leave it nil to fill the viewer. |
| `h1SizeEm` / `h2SizeEm` / `h3SizeEm` | `2.0 / 1.5 / 1.25` | Mirrors `Theme.gitHub`'s heading scale. Reading themes tone these down — heavy serif headings at the GitHub scale dominate the page and pull it toward "designed document" rather than "reader." |
| `showH1Rule` / `showH2Rule` | `true / true` | The horizontal rule under H1 and H2. Reading themes drop the H2 rule (too heavy for sustained reading) and keep a faded H1 rule for orientation. |

### Cross-theme rules

- **Code blocks always use the system monospace.** Even themes that bundle a serif body face should not bundle a separate code face — code in a serif theme reads better in mono than in a serif "code variant" anyway, and the contrast helps the eye skip code while reading prose.
- **The toolbar, sidebar, and window chrome stay system-themed.** The theme only restyles the article pane and lays a low-opacity tint over the sidebar's `NSVisualEffectView`. We do not retypeset the sidebar.
- **Backgrounds that aren't pure black or pure white.** Pure values fatigue the eye on long sessions. Even the "High Contrast" default leans on the system text-background color, which on macOS is off-white in light mode.
- **Heading color is not body color × black-amplifier.** A serif heading at body color looks bookish; a heading several stops darker reads as a UI label. We pick heading colors that are slightly darker than body or in the same hue family — the weight + size carry the hierarchy.

## Catalog

| Theme | Family | Body size | Line spacing | Heading scale | H1/H2 rules | Column max | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| High Contrast | system sans | 16 | 0.25em | 2.0 / 1.5 / 1.25 | yes / yes | none | Defaults straight through. |
| Sevilla | Alegreya (bundled) | 17 | 0.55em (≈1.6×) | 1.7 / 1.25 / 1.1 | faded / no | 620pt (≈75–78ch) | Long-form reading theme. |
| Charcoal | system sans | 16 | 0.25em | 2.0 / 1.5 / 1.25 | yes / yes | none | |
| Solarized Light | system sans | 16 | 0.25em | 2.0 / 1.5 / 1.25 | yes / yes | none | |
| Solarized Dark | system sans | 16 | 0.25em | 2.0 / 1.5 / 1.25 | yes / yes | none | |
| Phosphor | system sans | 16 | 0.25em | 2.0 / 1.5 / 1.25 | yes / yes | none | |
| Twilight | system sans | 16 | 0.25em | 2.0 / 1.5 / 1.25 | yes / yes | none | |

## Sevilla

> Long-form reading theme. Bundles Alegreya (Juan Pablo del Peral's Spanish-tradition serif, optimized for sustained text). Six weights ship under `mdv/Fonts/`: Regular, Italic, Medium, Bold, BoldItalic, ExtraBold (~1.7 MB total). Registered into the process-local font space at app launch — not installed on the user's system.

### What we changed and why

| Knob | Value | Reason |
| --- | --- | --- |
| `baseFontSize` | 17 | Alegreya's x-height runs slightly large; 17pt feels equivalent to 16pt SF for x-height while easing fatigue. |
| `paragraphLineSpacingEm` | 0.55 | Alegreya has pronounced ascenders/descenders; 0.25em (the gitHub default) feels cramped. 0.55 puts total leading at ≈1.6× — within the typography-designer reading target of 1.45–1.6×. |
| `articleMaxWidth` | 620pt | Caps the measure at ≈75–78ch at 17pt Alegreya. Any wider and lines run >85ch, where the eye loses the next-line pickup; any narrower (560pt → ~70ch) felt cramped in user testing. |
| `articleHorizontalPadding` | 30pt | Minimum gutter — kicks in when the window is narrower than `articleMaxWidth + 60`. |
| `h1SizeEm` | 1.7 | Down from 2.0. At 17pt body, that's ≈29pt H1 — heavy enough to anchor the page but not "magazine spread." |
| `h2SizeEm` | 1.25 | Down from 1.5. Lets the section header sit close to body weight; whitespace + bold weight do the separation. |
| `h3SizeEm` | 1.1 | Down from 1.25. Almost body-size; effectively just a bolded label. |
| `showH1Rule` | true | One quiet rule under H1 for orientation. Divider color is `#E6DEC2` — barely visible against the cream background. |
| `showH2Rule` | false | The H2 rule was the single heaviest "designed document" element. Removed. Spacing carries the break. |

### Color palette

| Slot | Hex | Notes |
| --- | --- | --- |
| `background` | `#F4EFE3` | Desaturated warm cream. Started at `#F8F1DE` (parchment) — that pulled too yellow in extended reading. |
| `secondaryBackground` | `#EAE5D6` | For code blocks and table stripes; deeper than the body but stays in the cream family. |
| `text` | `#42372C` | Soft warm brown. Subtly lighter than the heading — Alegreya is heavy by nature, so collapsing body and heading to the same dark value makes paragraphs feel oppressive. The lift puts a visible delta between body and H* without losing contrast against the cream (≈11:1, well above WCAG AA). Started at `#3B3026` ((0.23, 0.19, 0.15)) — close to heading; lifted ~7 per channel. |
| `secondaryText` | `#6A5C4D` | For blockquote text and similar de-emphasized prose. |
| `tertiaryText` | `#968874` | For very small captions and tertiary slots. |
| `heading` | `#2D2118` | Darker cordovan. Weight + size + the body↔heading color delta carry the hierarchy together. |
| `link` | `#2C5F8D` | Muted azulejo blue — the deep blue of glazed Spanish tile, instantly readable as a link without screaming. |
| `strong` | `#42372C` | Equal to body. Bold weight alone provides the emphasis — borrowing the heading's darkness for in-paragraph **bold** runs would re-introduce the same body↔heading collapse we just engineered out. **Sevilla-specific:** other themes leave `strong` at the heading darkness and rely on the contrast difference; we don't, because the heaviness of Alegreya at semibold already provides plenty of pop. |
| `border` / `divider` | `#E6DEC2` | Muted parchment. Used for the H1 rule, table borders, thematic breaks. Quiet on purpose. |
| `blockquoteBar` | `#B0623E` | Terracotta. The single warm accent in the palette. |

### Sevilla-specific deviations from the cross-theme defaults

These are not generalizable to other themes — they tune around Alegreya's specific weight/heft characteristics.

- **Body text is not heading darkness.** With most fonts the body and heading can sit at the same hue with weight + size carrying the hierarchy. Alegreya is *heavy* — set body to heading-darkness and a paragraph reads as a wall. Body at `#42372C` is one stop lighter than heading `#2D2118` so paragraphs breathe.
- **`strong` (in-paragraph bold) inherits body color, not heading color.** Bold Alegreya at heading darkness pops too hard mid-paragraph and re-creates the body↔heading collapse we lifted body to avoid. Bold weight alone is enough emphasis.
- **H2 has no rule, H1 has a faded rule.** The default theme shows both because system sans-serif headings need the rule to read as breaks. Alegreya at any size already announces itself as a heading; rules add unnecessary mass.

### What we explicitly did NOT do

- **Bundle a code monospace.** System mono is fine. A serif theme with a serif "code style" loses the prose-vs.-code visual hint.
- **Justify body text.** Left-rag stays — justified prose without a real shaping engine creates rivers and feels worse than left-aligned.
- **Drop caps or ornamental flourishes.** This is a viewer, not a PDF designer. Restraint reads better.
