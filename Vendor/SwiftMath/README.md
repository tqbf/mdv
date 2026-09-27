# SwiftMath (vendored)

Upstream: https://github.com/mgriebling/SwiftMath — v1.7.3, MIT (see LICENSE).

Vendored rather than pulled in as a SwiftPM dependency because upstream
ships its fonts as a SwiftPM resource bundle, and the generated
`Bundle.module` accessor only looks for that bundle at the root of the app
bundle — where codesign refuses to sign it. mdv ships the fonts in
`Contents/Resources/mathFonts.bundle` (copied by `build.sh`) instead.

Local changes vs upstream:

- `Sources/SwiftMath/MathFontBundle.swift` (new) resolves the font bundle
  from `Bundle.main`, falling back to `Vendor/SwiftMath/mathFonts.bundle`
  for `swift run`.
- `MathBundle/MathFont.swift` and `MathRender/MTFont.swift`: the three
  `Bundle.module.url(forResource: "mathFonts", …)` calls now read
  `MathFontBundle.url`.
- `MathRender/MTMathList.swift`: `MTMathAtom.init(type:value:)` is `public`
  (upstream: internal) so `mdv/MathRenderer.swift` can register symbols
  upstream lacks (`\gtrsim`, `\therefore`, `\iint`, …) via
  `MTMathAtomFactory.add(latexSymbol:value:)`.
- `\boxed{…}` support (upstream has none): `MTBoxed` atom in
  `MathRender/MTMathList.swift` (an `MTOverLine` subclass, so it shares the
  `.overline` type and every existing switch), parsing in
  `MTMathListBuilder.swift`, `MTBoxDisplay` in `MTMathListDisplay.swift`,
  and `makeBoxed` in `MTTypesetter.swift`.
- `mathFonts.bundle` is trimmed to Latin Modern Math (the only font mdv
  uses) plus its GUST license. Upstream ships eleven more; copy them in
  from upstream if you ever want to offer a math font choice.
- Tests and the `Package.swift` are not vendored; the target is declared in
  the root `Package.swift`.
