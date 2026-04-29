# Typography Decisions

Tracks per-theme type-style work. Every theme gets a row in the **Catalog** table; the **Conventions** section captures rules that apply across themes.

## Conventions

These are the cross-theme defaults set on `MDVTheme` in `mdv/ThemeManager.swift`. They started as a one-to-one mirror of `Theme.gitHub`; we've tuned them away from that baseline as we've built reading and operational themes side by side. Each theme can override piece-by-piece.

### Type and measure

| Field | Default | Why |
| --- | --- | --- |
| `bodyFontFamily` | `.system()` | Inherit SF Pro on macOS. Set to `.custom("…")` on themes that bundle a face. |
| `baseFontSize` | `16pt` | macOS body baseline. Themes nudge per font: Sevilla → 17 (Alegreya x-height), Charcoal → 16.5 (half-pt SF crispness). |
| `paragraphLineSpacingEm` | `0.30` (≈1.5× total) | Up from MarkdownUI's 0.25. Sits in the 1.45–1.6× comfort zone for both prose and technical reading. Reading themes push higher (Sevilla 0.55); operational themes drop back to 0.25 (Charcoal). |
| `articleHorizontalPadding` | `40pt` | Default left/right gutter when not max-width-constrained, or when the window is narrower than `articleMaxWidth`. |
| `articleMaxWidth` | `860pt` (≈95–100ch at 16pt SF) | Caps line length so an article doesn't run edge-to-edge on a 27" display. Reading themes go narrower (Sevilla 620 ≈75ch); utility themes go wider (Charcoal 920 ≈110ch). |

### Heading scale & rules

| Field | Default | Why |
| --- | --- | --- |
| `h1SizeEm / h2SizeEm / h3SizeEm` | `1.75 / 1.4 / 1.15` | Down from MarkdownUI's `2.0 / 1.5 / 1.25`. The GitHub scale reads as "designed document" — too heavy for both reading and operational use. Weight + spacing carry hierarchy now, with size as a secondary cue. |
| `showH1Rule` | `true` | Single rule under H1 for orientation. Each theme picks its own divider color; quieter is better. |
| `showH2Rule` | `false` | Down from `true`. The H2 rule stacks visually with the H1 rule and produces "designed document" mass. Themes that genuinely want section-break rules can flip it back on. |

### Per-element vertical spacing

`paragraphBottomSpacing`, plus `h{1,2,3}TopSpacing` / `h{1,2,3}BottomSpacing`. Defaults are MarkdownUI's GitHub-mirror values (`24` top / `16` bottom for headings, `16` after paragraphs). Themes use these to tune rhythm:

- **Operational rhythm** (Charcoal): `0/14`, `26/10`, `18/8`, paragraph `11`. Tight.
- **Reading rhythm** (Sevilla): `28/18`, `32/12`, `22/8`, paragraph `14`. Generous.

### Color

| Field | Convention | Why |
| --- | --- | --- |
| `text` (body) | Distinct from `heading` — never the same value | If body matches heading, paragraphs read as a wall, especially with heavier-weight typefaces. Each theme picks its own delta. |
| `strong` | Tier depends on the typeface — see below | The `strong` color is the bigger judgment call. |
| `accent` | Theme-specific color for in-viewer interactive affordances (bookmark-hover stripe, hovered-block tint) | Defaults to system `.accentColor` (system blue). That clashes inside themed surfaces (a system-blue stripe on a Sevilla cream page reads as UI chrome). Each themed theme should override; Sevilla → terracotta, Charcoal → muted GitHub blue. |

### The `strong` tier rule

In-paragraph bold (`**…**`) emphasis sits at one of three brightness tiers:

1. **`strong = body`** — bold weight alone provides the emphasis. Use when the typeface's semibold/bold weight is naturally heavy enough mid-paragraph (Alegreya is). **Sevilla.**
2. **`strong = body lifted` (between body and heading)** — bold weight *plus* a half-step brightness lift. Use when the typeface's semibold is too soft to register on its own (system sans-serifs). **Charcoal:** `body #C9D1DB` < `strong #EBF0F7` < `heading #F5F7FC`.
3. **`strong = heading`** — what `Theme.gitHub` does. **Don't.** Mid-paragraph bold runs at heading-darkness re-introduce the body↔heading collapse and pull the paragraph back toward a wall of text. Avoid unless a theme has a very specific reason.

Each theme should pick a tier explicitly and document the choice.

### Cross-theme rules (not knobs)

- **Code blocks always use the system monospace.** Even themes that bundle a serif body face should not bundle a separate code face. The mono/serif visual contrast helps the eye skip code while reading prose.
- **The toolbar, sidebar, and window chrome stay system-themed.** The theme only restyles the article pane and lays a low-opacity tint over the sidebar's `NSVisualEffectView`. The sidebar isn't retypeset.
- **Backgrounds that aren't pure black or pure white.** Pure values fatigue the eye on long sessions.
- **Heading color is in the same hue family as body, slightly darker (or brighter, in dark mode).** A heading several stops removed reads as a UI label, not part of the document. Weight + size carry the rest of the hierarchy.

## Catalog

(Defaults: SF Pro 16pt, 0.30em line spacing, 1.75 / 1.4 / 1.15 heading scale, H1 rule on / H2 rule off, 860pt column max, `strong` tier 3 — overridden where noted.)

| Theme | Family | Body size | Line spacing | Heading scale | H1/H2 rules | Column max | Strong tier | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| High Contrast | system sans | 16 | 0.30em | 1.75 / 1.4 / 1.15 | yes / no | 860pt | tier 1 (= body) | Defaults + tier-1 strong + system-blue accent. |
| Sevilla | Alegreya (bundled) | 17 | 0.55em (≈1.6×) | 1.7 / 1.25 / 1.1 | faded / no | 620pt (≈75ch) | tier 1 (= body) | Long-form reading theme. Terracotta accent. |
| Charcoal | system sans | 16.5 | 0.25em (≈1.46×) | 1.82 / 1.45 / 1.15 | faded / no | 920pt (≈110ch) | tier 2 (lifted) | "GitHub README, dark, all business." Muted-blue accent. |
| Solarized Light | system sans | 16 | 0.30em | 1.75 / 1.4 / 1.15 | yes / no | 860pt | tier 1 (= body) | Defaults + Solarized orange accent. |
| Solarized Dark | system sans | 16 | 0.30em | 1.75 / 1.4 / 1.15 | yes / no | 860pt | tier 2 (lifted) | Defaults + Solarized yellow accent. |
| Phosphor | system sans | 16 | 0.30em | 1.75 / 1.4 / 1.15 | yes / no | 860pt | tier 1 (= body) | Defaults + amber accent (CRT vibe). |
| Twilight | system sans | 16 | 0.30em | 1.75 / 1.4 / 1.15 | yes / no | 860pt | tier 2 (lifted) | Defaults + cream accent. |

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

## Charcoal

> "GitHub README, dark, all business." Compact, neutral, high density. Tuned for technical reading — internal docs, READMEs, design notes — not long-form prose.

### What we changed and why

| Knob | Value | Reason |
| --- | --- | --- |
| `bodyFontFamily` | `.system()` (SF Pro) | Apple's hinting + weight behavior on macOS is excellent at small sizes; no decorative face. |
| `baseFontSize` | 16.5 | Half-pt nudge above the 16pt default — the difference between "default" and "tuned" at SF Pro at this column width. |
| `paragraphLineSpacingEm` | 0.25 (≈1.46× total) | Operational, not literary. The cross-theme default is 0.30; Charcoal tightens. |
| `articleMaxWidth` | 920pt (≈110ch) | Wider than the cross-theme default — technical docs scan better with a wider measure than prose does. |
| `h1SizeEm` / `h2SizeEm` / `h3SizeEm` | 1.82 / 1.39 / 1.15 | = 30pt / 23pt / 19pt at the 16.5pt body. Slightly larger than the new cross-theme default — SF Pro can take a bit more size at heading weights and still read as a UI document. |
| Vertical rhythm | h1 0/14, h2 26/10, h3 18/8, p 11 | The user-supplied "operational rhythm" spec. |
| `showH2Rule` | false | Same call as Sevilla; the H2 rule reads as designed-document mass. |
| `accent` | `#2E7AEB` (muted GitHub blue) | The bookmark-hover stripe and hovered-block tint inherit this — a calmer blue than system `.accentColor`. |

### Color palette

| Slot | Hex | Notes |
| --- | --- | --- |
| `background` | `#1E1F25` | Cool dark grey-blue. Pulls toward GitHub's bg without going pure-black; pure black makes large white-ish glyphs ring against the screen. |
| `secondaryBackground` | `#2E303B` | Code-block / inline-code pill background. |
| `text` | `#C9D1DB` | Muted cool-grey body. Sits clearly below heading-white so paragraphs don't max out brightness. |
| `secondaryText` | `#94A1B0` | Blockquote text, de-emphasized prose. |
| `tertiaryText` | `#6E7785` | Small captions. |
| `heading` | `#F5F7FC` | Almost-white. Pure white is reserved for nothing in this theme — even max-emphasis text sits at this off-white. |
| `link` | `#5CA3FA` | GitHub-style blue, less saturated than `#6FB1FF`. No underline by default. |
| `strong` | `#EBF0F7` | **Tier 2 (lifted).** Sits between body and heading: bold weight + half-step brightness lift. SF Pro semibold is too soft to register on its own as emphasis at 16.5pt body; Sevilla doesn't need this because Alegreya semibold already pops. |
| `border` / `divider` / `blockquoteBar` | `#3D4554` | Single muted rule color used for table borders, the H1 rule, and the blockquote left bar. Neutral grey — the previous bright accent felt like UI focus chrome. |

### Charcoal-specific deviations from the cross-theme defaults

- **`strong` is tier 2, not tier 1.** Sevilla collapses body and strong to the same value because Alegreya is heavy. SF Pro semibold isn't, so Charcoal lifts strong to a third tier between body and heading.
- **`articleMaxWidth` 920 (wider than default 860).** Technical reading scans better wider than prose does. Sevilla goes the other direction (620, narrower).
- **`paragraphLineSpacingEm` 0.25 (tighter than default 0.30).** GitHub-doc density.
- **Custom `accent` color.** The system `.accentColor` is a saturated blue that visually competes with the heading whites and bg darks. The muted `#2E7AEB` reads as a quieter affordance.
