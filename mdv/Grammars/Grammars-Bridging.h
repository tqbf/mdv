#ifndef MDV_GRAMMARS_BRIDGING_H
#define MDV_GRAMMARS_BRIDGING_H

// Forward-declare TSLanguage as an opaque struct so Swift can hold pointers
// to it (as OpaquePointer) without pulling in tree-sitter's C headers from
// the SwiftTreeSitter SPM target into the bridging context. The actual
// runtime layout is supplied by SwiftTreeSitter's bundled libtree-sitter.
typedef struct TSLanguage TSLanguage;

// One extern per vendored grammar in mdv/Grammars/<lang>/parser.c. Each
// returns the bundled grammar's TSLanguage, suitable for passing into
// SwiftTreeSitter's Language(language:) initializer.
const TSLanguage *tree_sitter_c(void);
const TSLanguage *tree_sitter_go(void);
const TSLanguage *tree_sitter_rust(void);
const TSLanguage *tree_sitter_bash(void);
const TSLanguage *tree_sitter_javascript(void);
const TSLanguage *tree_sitter_yaml(void);
const TSLanguage *tree_sitter_toml(void);
const TSLanguage *tree_sitter_python(void);
const TSLanguage *tree_sitter_ruby(void);

#endif
