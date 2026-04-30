# On Reading Long-Form on a Glowing Rectangle

This document is intentionally text-heavy — the goal is to exercise
the *reading* themes (Sevilla, Solarized Light) the way they were
meant to be read, and to give long paragraphs to the search/find
machinery and the find-hit highlighter.

Try toggling between **Sevilla** and **Charcoal** while reading. The
typography difference is striking: Sevilla bumps the body to 17pt
Alegreya with 1.6× leading and caps the column at ~620pt; Charcoal
goes the opposite direction with 16.5pt SF Pro, 1.46× leading, 920pt
column, and an operational rather than literary rhythm.

## I.

There is a kind of secondhand romance to typography on screens —
phototypesetting, then desktop publishing, then web type, then
finally screen type that knows it's screen type — that we don't
talk about often enough. The earliest digital faces were optimized
for laser printers. The earliest *web* faces were anything Times
or Verdana. ClearType, Quartz subpixel rendering, and finally
retina displays each broke a generation of careful kerning. Then
variable fonts arrived and unlocked everything at once: weight,
width, optical size, slant, all addressable from CSS or SwiftUI's
font system without spinning up a different font file.

It's tempting, when designing a markdown viewer, to just pick a
nice serif and call it done. But "nice serif" is a design
question disguised as a default — and the answers are different
for a 13-inch laptop, a 27-inch monitor, and a 6-inch phone. Even
the same serif renders differently on each surface. So the more
honest move is to ship a few opinionated themes, each one
tuned end-to-end (column width, line height, heading scale,
accent color, code palette), and let the reader pick the one that
matches the surface and the moment.

## II.

The hardest constraint in long-form reading typography is not
beauty. It's *time*. Most readers will spend twenty minutes with
a piece. After ten minutes, eye fatigue is the limiting factor,
not comprehension. After fifteen, posture. After twenty, the
small things — the half-pixel of inter-glyph spacing you sweated
over — vanish into the rest of the experience. So the small
things have to be invisible-but-present, the way a good sound
mix is invisible-but-present in a film.

This means the right test for a reading theme isn't *how does it
look?* but *how do you feel after twenty minutes of reading on
it?* Sevilla was tuned to that test. The cream background reduces
the white-screen flare that drives twitchy eye motion. Alegreya
has a comparatively low contrast and large x-height, which keeps
words looking like words rather than puzzles when peripheral
vision picks them up. The 1.6× leading is generous compared to
typical web body copy (1.4×–1.5×) — but it pays off on long
paragraphs, where a tight leading visually merges adjacent lines
and forces a reader to re-find their place after every saccade.

The terracotta accent ties the palette together without trying
to be a fashion statement. It's there for the bookmark stripe,
the hover affordance, the H1 rule — small interactions that
shouldn't shout. The "shouting accent" pattern (saturated, eye-
catching, brand-aligned) is fine for landing pages. It's
exhausting on a 4,000-word essay.

## III.

Code styling in a reading theme is its own minor art form. Code
shouldn't look like prose, because it isn't prose: the spatial
arrangement of tokens carries information. But it also shouldn't
look like a *terminal*, with its high-contrast token explosion,
because that breaks the eye out of reading mode every time the
prose dips into a fenced block.

The Sevilla code palette tries to thread this needle. It maps
keywords to a deep terracotta (close to but not exactly the
heading color), strings to a walnut brown, comments to the
tertiaryText grey, function names to azulejo blue (matching the
link color in the prose), and types to raw umber. Numbers and
constants share an umber tone. The palette as a whole sits at
roughly the same value as the body text — so a code block doesn't
*pop* the way a GitHub-Light code block does, it just sits on the
page like a variant texture.

This is opinionated. Some readers prefer terminal-style code; some
prefer something closer to GitHub-Light's saturated keywords. So
mdv ships an alternative palette per theme, and the alternative
isn't a paint job applied on top — it's a separately-tuned set of
colors that fits that theme's overall feel.

## IV.

Charcoal exists as the operational opposite of Sevilla. Where
Sevilla is for prose, Charcoal is for technical reading. READMEs.
Internal docs. Postmortem write-ups. The Charcoal background
(`#1B1B21`) is cool rather than warm, the body face is SF Pro
(geometric, neutral, perfectly legible at small sizes), the
column runs out to ~920pt because technical docs want to scan
horizontally, and the leading drops to 1.46× because compactness
is a feature when you're navigating a wall of API surface.

The code palette for Charcoal is GitHub Dark, more or less —
vivid token semantics, high contrast against the cool grey-blue
chrome. Code blocks in Charcoal *should* pop, because they're
likely the thing you opened the file to read.

## V.

So: Sevilla for the essay, Charcoal for the README. Both for the
same renderer. That's the small wager this app is making — that
"the right typography depends on what you're reading" is more
true than "one well-tuned default fits everyone."

You can argue with this. Many people do. But until you've spent
two hours reading a 12,000-word piece on Charcoal and another
two hours reading the SwiftUI documentation on Sevilla, you might
be surprised which combination feels less right.

## VI.

A short coda about long sentences: a single sentence, on its own,
can stretch across a thousand characters of clauses and asides
and parentheticals before reaching its proper subject and then
its predicate, and that kind of sentence is the right test for a
column width — because at the wrong column width it falls apart
into rhythmless fragments, and at the right column width it sings.

(That sentence was 67 words. Hemingway would not approve. But
this is a typography test, not a style guide, and the question we
care about is whether the eye gets lost making the return saccade
from end of line to start of next.)

## Coda

Open this file in different themes. See what happens to your
shoulders after twenty minutes.
