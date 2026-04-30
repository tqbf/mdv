# Vendored tree-sitter grammars

Each subdirectory holds a grammar's parser source (parser.c, optional scanner.c/cc, vendored tree_sitter/ headers) plus its highlights.scm query file. Pinned commits below.

| Language | Repo | Commit |
| --- | --- | --- |
| c | https://github.com/tree-sitter/tree-sitter-c | `b780e47fc780ddc8da13afa35a3f4ed5c157823d` |
| go | https://github.com/tree-sitter/tree-sitter-go | `2346a3ab1bb3857b48b29d779a1ef9799a248cd7` |
| rust | https://github.com/tree-sitter/tree-sitter-rust | `77a3747266f4d621d0757825e6b11edcbf991ca5` |
| bash | https://github.com/tree-sitter/tree-sitter-bash | `a06c2e4415e9bc0346c6b86d401879ffb44058f7` |
| javascript | https://github.com/tree-sitter/tree-sitter-javascript | `58404d8cf191d69f2674a8fd507bd5776f46cb11` |
| yaml | https://github.com/ikatyang/tree-sitter-yaml | `0e36bed171768908f331ff7dff9d956bae016efb` |
| toml | https://github.com/ikatyang/tree-sitter-toml | `8bd2056818b21860e3d756b5a58c4f6e05fb744e` |
| python | https://github.com/tree-sitter/tree-sitter-python | `26855eabccb19c6abf499fbc5b8dc7cc9ab8bc64` |
| ruby | https://github.com/tree-sitter/tree-sitter-ruby | `ad907a69da0c8a4f7a943a7fe012712208da6dee` |

## Notes

- YAML and TOML had their scanner `#include <tree_sitter/parser.h>` patched to quoted form so the include resolves to the local `tree_sitter/parser.h` shipped beside each scanner. No other source changes.
- YAML's `scanner.cc` `#include`s `schema.generated.cc` directly; that companion file lives next to scanner.cc but is **not** added as a separate compile unit in the pbxproj.
- YAML had no `queries/highlights.scm` upstream; we vendored `runtime/queries/yaml/highlights.scm` from nvim-treesitter.
- Bumping a grammar: clone fresh, re-copy `src/` and `queries/highlights.scm` (or nvim-treesitter equivalent), reapply the `<…>` → `"…"` patch where needed, update the row above.
