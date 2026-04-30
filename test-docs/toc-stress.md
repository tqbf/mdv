# TOC Stress Test

Lots of headings at every level. Open the inspector (⌥⌘0) and try the
spyglass-collapse "Filter headings" search.

## Setup

### Goals

#### Verify the TOC pane

#### Verify the search animation

#### Verify the level-based indentation

### Scope

#### What's tested

#### What's not tested

## Architecture

### Build system

#### SwiftPM target graph

#### CGrammars C target

#### Bundling shell script

### Application

#### App entry point

#### Window scene

#### Toolbar configuration

#### Notification routing

### Themes

#### MDVTheme struct

#### Palette catalogue

#### Code palette mapping

#### Window-level appearance

## Features

### Find

#### In-document find bar

#### Inline hit highlighting

#### Block-level tint fallback

#### Cmd-G / Shift-Cmd-G navigation

### History

#### File-tracked entries

#### Persistent across launches

#### FTS-backed cross-document search

### Bookmarks

#### Per-file bookmarks

#### Numbered slots (Cmd-1 … Cmd-9)

#### Placeholder slot (Cmd-0)

### TOC

#### Heading extraction

#### Active-block tracking

#### Filter / search

### External editor

#### Toolbar pencil button

#### File menu submenu

#### Persistent choice (@AppStorage)

### Live reload

#### FSEvents-backed watcher

#### Atomic-rename safety

#### Path resolution

### Images

#### Relative paths

#### Absolute file URLs

#### data: URIs

#### http(s) fallback

#### Missing-asset placeholder

## Themes

### High Contrast

### Sevilla

#### Body face: Alegreya

#### Column: 620pt

#### Code palette: earth tones

### Charcoal

#### Body face: SF Pro

#### Column: 920pt

#### Code palette: GitHub Dark

### Solarized Light

#### Background: base3 cream

#### Code palette: canonical Schoonover

### Solarized Dark

### Phosphor

#### Background: pure black

#### Body color: amber

#### Code: monochrome amber

### Twilight

#### Background: deep navy

#### Heading: mint

#### Link: cream

## Notes

### Limitations

#### Math rendering

#### Mermaid diagrams

#### Print to PDF

### Known quirks

#### Tables overflow narrow themes

#### Inline highlight strips heading sizing

#### data: URI render uses NSImage(data:)

## Acknowledgments

### Open source dependencies

#### swift-markdown-ui

#### SwiftTreeSitter

#### tree-sitter grammar authors

### Inspiration

#### markless

#### typora

#### Marked 2

## Closing

This document has roughly 60 headings across H1–H4 levels. The TOC
should show every one of them with proper indentation. Filter for
"code" or "palette" to test the case-insensitive search.
