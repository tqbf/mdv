# Mermaid WKWebView fallback

A grab-bag of Mermaid diagram types BeautifulMermaid doesn't speak,
all of which should render via the bundled `mermaid.min.js` running in
a WKWebView. If any of them fall back to the "Mermaid diagram could
not be rendered" plate, the dispatcher in `MermaidRenderer.swift` is
miscategorising the keyword. If the diagram itself looks broken, that
points at `MermaidWebRenderer.swift` or the bundled mermaid.js
version pin in `build.sh`.

Companion to [gantt.md](gantt.md), which exercises a single longer
diagram. This file trades depth for breadth.

## Pie

```mermaid
pie title Project time by area
    "Engineering" : 45
    "Design"      : 20
    "Ops"         : 15
    "Meetings"    : 20
```

## Timeline

```mermaid
timeline
    title Release history
    2024 : 0.1 — first commit
         : 0.2 — themes
    2025 : 0.5 — bookmarks
         : 0.7 — Mermaid (native)
    2026 : 0.8 — Mermaid (web fallback)
```

## Mindmap

```mermaid
mindmap
  root((mdv))
    Rendering
      MarkdownUI
      Tree-sitter
      Mermaid
        BeautifulMermaid
        WKWebView fallback
    UI
      Sidebar
      TOC
      Bookmarks
    Themes
      Light
      Dark
      Reading
```

## User journey

```mermaid
journey
    title A morning with mdv
    section Open
      Drag folder onto window: 5: User
      Sidebar populates: 4: mdv
    section Read
      Skim README: 5: User
      Click through cross-link: 5: User, mdv
    section Edit
      ⌘E into editor: 4: User
      Save and live-reload: 5: mdv
```

## Quadrant chart

```mermaid
quadrantChart
    title Feature triage
    x-axis Hard --> Easy
    y-axis Low impact --> High impact
    quadrant-1 Do now
    quadrant-2 Schedule
    quadrant-3 Drop
    quadrant-4 Quick wins
    Mermaid web fallback: [0.7, 0.8]
    Style picker for web path: [0.4, 0.3]
    Snapshot-based PNG export: [0.2, 0.6]
    Drop the KVC hack: [0.85, 0.55]
```

## Requirement diagram

```mermaid
requirementDiagram
    requirement supported_types {
        id: 1
        text: BeautifulMermaid covers six diagram families.
        risk: low
        verifymethod: test
    }

    requirement web_fallback {
        id: 2
        text: Anything else renders via bundled mermaid.js.
        risk: medium
        verifymethod: demonstration
    }

    element dispatcher {
        type: function
    }

    dispatcher - satisfies -> supported_types
    dispatcher - satisfies -> web_fallback
```

## With a mermaid preamble

This block opens with a `%%{init}%%` directive *and* a comment
before the diagram keyword. The dispatcher should still see it as
a flowchart and route it through the native path; if it ends up in
the WKWebView fallback, `firstMermaidDirectiveLine` is broken.

```mermaid
%%{init: { "theme": "default" } }%%
%% This is a comment, not a diagram keyword.
flowchart LR
    A[Source] --> B{Native?}
    B -- yes --> C[BeautifulMermaid]
    B -- no  --> D[WKWebView]
```
