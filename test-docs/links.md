# Link Behavior

mdv intercepts link clicks via `OpenURLAction` so md-to-md
references navigate inline; everything else falls through to the
system handler. Each row below documents what *should* happen on
click — try them.

## Markdown links (in-app navigation)

Same-directory:

- [README](README.md)
- [Syntax tour](syntax.md)
- [Code samples](code.md)
- [Tables](tables.md)
- [Images](images.md)
- [Prose](prose.md)
- [TOC stress test](toc-stress.md)

Markdown link with explicit `./` prefix:

- [Syntax (with ./ prefix)](./syntax.md)

Markdown link with a `.markdown` extension instead of `.md`:

- [Hypothetical .markdown file](./does-not-exist.markdown)
  → falls through to the system handler since the file doesn't
  exist; macOS's "no application" dialog will appear.

## Same-document fragment

These use heading-anchor syntax. Currently mdv passes them through
to the default handler — fragment navigation isn't implemented yet.

- [Jump to "Edge cases" section](#edge-cases)
- [Jump to "Markdown links" up top](#markdown-links-in-app-navigation)

## External URLs (open in default browser)

- HTTPS: [Apple developer docs](https://developer.apple.com/documentation/swiftui)
- HTTP (rare): [example.com](http://example.com)
- mailto: [Email someone](mailto:nobody@example.com)
- Custom scheme: [Slack deep link](slack://open)
  → tries to launch Slack if installed; otherwise the system shows a
  "no application configured" dialog.

## Local non-markdown files

These resolve to a file on disk that isn't markdown, so mdv hands
them off to the system. macOS opens the registered handler (Preview
for images, default browser for HTML, etc.).

- [The icon image](images/icon.png)
- [The banner image](images/banner.png)

## Things that should fail gracefully

- [Broken markdown ref](./not-here.md)
  → fallthrough to system; the OS will probably try to open mdv on
  a non-existent path.
- [Broken absolute path](file:///nope/missing.md)
  → fallthrough.
- [Empty link]()
  → does nothing useful.

## Reference-style and inline-title links

Inline link with title attribute:
[hover for tooltip](https://github.com "GitHub homepage").

> **Known gap:** the title attribute (the quoted string) doesn't
> surface as a hover tooltip. SwiftUI's `Text(AttributedString)` on
> macOS doesn't render link titles as tooltips, and we'd need to
> drop the AttributedString inline path for an `NSTextView`-backed
> renderer to do per-link `.help(...)` regions.

Reference style:

[reference]: https://example.com "Example.com (reference)"

[Click the reference][reference] above. Reference labels are
case-insensitive in CommonMark — [REFERENCE][reference] works too.

## Autolinks

Plain URL (CommonMark autolink): <https://github.com>.

Email autolink: <hello@example.com>.

GFM-style bare URL: https://example.com (renders as a link without
angle brackets, depending on the parser).

## Edge cases

A link nested inside emphasis: *[an italic link](https://example.com) in italic prose*.

A link inside a code span: `[not a link](url)` (should be plain
inline code, not a link).

A long URL that wraps: [an absurdly long URL with lots of query
parameters that the line should wrap on at narrower
widths](https://example.com/path/to/something?with=lots&of=query&parameters=that&push=the&line=very-far-right).

Adjacent links:
[A](#)[B](#)[C](#) (no spaces between).

Link with image inside (the standard CommonMark "clickable image"
pattern):
[![inline icon](images/icon.png)](https://github.com)

> **Known gap:** MarkdownUI's inline renderer drops images that
> appear inside other inline contexts (links, emphasis), because
> SwiftUI `AttributedString` can't embed inline images. Block-level
> images render fine (see [images.md](images.md)); but
> `[![alt](src)](url)` collapses to just the link with no visible
> content. Fixing this would mean splitting inline runs into a
> Text+Image composition or replacing the renderer entirely.
