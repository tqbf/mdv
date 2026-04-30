# Tables

GFM table syntax. mdv renders tables via MarkdownUI; alignment, narrow
cells, wide cells, and inline-formatting inside cells should all work.

## Basic

| Theme           | Light/Dark | Best for       |
|-----------------|------------|----------------|
| High Contrast   | Light      | Default        |
| Sevilla         | Light      | Reading prose  |
| Charcoal        | Dark       | Technical docs |

## Alignment

| Left aligned | Centered | Right aligned |
|:-------------|:--------:|--------------:|
| 1            |    a     |          $1.00|
| 22           |    bb    |         $22.50|
| 333          |   ccc    |        $333.99|

## Narrow + wide cells

| Key | Description |
|-----|-------------|
| ⌘O  | Open file. The standard macOS open dialog, scoped to markdown extensions. The history sidebar adds the file once it loads. |
| ⌘F  | Find in document. Spawns the find bar; matches highlight inline. |
| ⌥⌘0 | Toggle the right inspector (TOC + bookmarks). |
| ⌘D  | Bookmark the current spot. Subsequent ⌘D toggles it off. |
| ⌘E  | Edit current file in your chosen external editor. |

## Inline formatting in cells

| Style          | Demo                                |
|----------------|-------------------------------------|
| **Bold**       | **Important point**                 |
| *Italic*       | *aside, gentle emphasis*            |
| `Code`         | `Bundle.main.url(forResource: ...)` |
| ~~Strike~~     | ~~deprecated~~ → use the new API    |
| [Link](#)      | [Click me](https://example.com)     |
| Mixed          | **Bold _italic_** with `code` too   |

## Many columns

| Lang  | Hello                       | Loop                              | Comment   |
|-------|-----------------------------|-----------------------------------|-----------|
| C     | `printf("hi\n");`           | `for (int i=0; i<n; i++)`         | `//` `/**/`|
| Go    | `fmt.Println("hi")`         | `for i := 0; i < n; i++`          | `//` `/**/`|
| Rust  | `println!("hi");`           | `for i in 0..n`                   | `//` `/**/`|
| Py    | `print("hi")`               | `for i in range(n):`              | `#`        |
| JS    | `console.log("hi")`         | `for (let i = 0; i < n; i++)`     | `//` `/**/`|
| Ruby  | `puts "hi"`                 | `n.times do |i| ... end`          | `#`        |
| Bash  | `echo hi`                   | `for i in {1..n}; do ... done`    | `#`        |

## A table that's wider than the column

If your theme has a tight `articleMaxWidth` (Sevilla → 620pt), this
table will probably overflow horizontally. That's a GFM-renderer
quirk; tables don't wrap their cells, they just clip or push the
column.

| Slim | Slim2 | Long | Wider | Even wider | The widest column has a lot of words in it just to push things |
|------|-------|------|-------|------------|----------------------------------------------------------------|
| a    | b     | c    | d     | e          | filler                                                         |
| 1    | 2     | 3    | 4     | 5          | filler                                                         |

## Empty cells

| A | B | C |
|---|---|---|
| 1 |   | 3 |
|   | 2 |   |
| 1 | 2 | 3 |
