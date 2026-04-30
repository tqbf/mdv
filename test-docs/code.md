# Code Highlighting Tour

One block per bundled tree-sitter grammar. Switch between Charcoal
(GitHub Dark palette), Solarized Dark, and Phosphor (monochrome amber)
to compare how each palette assigns colors to the same tokens.

## Bash

```bash
#!/usr/bin/env bash
# Build mdv with SwiftPM and assemble a .app bundle.
set -euo pipefail

CONFIG="${1:-debug}"
case "$CONFIG" in
  debug|release) ;;
  *) echo "usage: $0 [debug|release]"; exit 1 ;;
esac

cd "$(dirname "$0")"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/mdv"

APP="build/mdv.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/mdv"

echo "✓ built $APP"
```

## C

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char *name;
    int   age;
} Person;

static Person *person_new(const char *name, int age) {
    Person *p = malloc(sizeof *p);
    if (!p) return NULL;
    p->name = strdup(name);
    p->age = age;
    return p;
}

int main(int argc, char **argv) {
    Person *p = person_new("Ada", 36);
    printf("Hello, %s (%d)\n", p->name, p->age);
    free(p->name);
    free(p);
    return EXIT_SUCCESS;
}
```

## Go

```go
package main

import (
    "fmt"
    "log"
    "net/http"
)

type Server struct {
    addr string
    mux  *http.ServeMux
}

func NewServer(addr string) *Server {
    s := &Server{addr: addr, mux: http.NewServeMux()}
    s.mux.HandleFunc("/", s.handleRoot)
    return s
}

func (s *Server) handleRoot(w http.ResponseWriter, r *http.Request) {
    fmt.Fprintf(w, "hello from %s\n", r.URL.Path)
}

func main() {
    s := NewServer(":8080")
    log.Printf("listening on %s", s.addr)
    log.Fatal(http.ListenAndServe(s.addr, s.mux))
}
```

## JavaScript

```javascript
// Tagged template that reads like SQL but really concatenates safely.
const sql = (strings, ...values) =>
  strings.reduce((acc, str, i) => acc + str + (i < values.length ? `$${i + 1}` : ""), "");

async function findUser(db, id) {
  const text = sql`SELECT * FROM users WHERE id = ${id}`;
  const { rows } = await db.query({ text, values: [id] });
  return rows[0] ?? null;
}

class Cache extends Map {
  get(key, fallback) {
    if (super.has(key)) return super.get(key);
    const v = typeof fallback === "function" ? fallback() : fallback;
    super.set(key, v);
    return v;
  }
}

export { findUser, Cache };
```

## Python

```python
"""A toy LRU cache built on collections.OrderedDict."""

from __future__ import annotations
from collections import OrderedDict
from typing import Generic, TypeVar, Optional

K = TypeVar("K")
V = TypeVar("V")


class LRU(Generic[K, V]):
    def __init__(self, capacity: int) -> None:
        if capacity <= 0:
            raise ValueError("capacity must be positive")
        self._capacity = capacity
        self._items: OrderedDict[K, V] = OrderedDict()

    def get(self, key: K) -> Optional[V]:
        if key not in self._items:
            return None
        self._items.move_to_end(key)
        return self._items[key]

    def put(self, key: K, value: V) -> None:
        if key in self._items:
            self._items.move_to_end(key)
        self._items[key] = value
        if len(self._items) > self._capacity:
            self._items.popitem(last=False)


if __name__ == "__main__":
    cache: LRU[str, int] = LRU(2)
    cache.put("a", 1)
    cache.put("b", 2)
    cache.put("c", 3)         # evicts "a"
    assert cache.get("a") is None
    print(cache.get("b"))
```

## Ruby

```ruby
# A minimal Sinatra-ish DSL — wires lambdas to verb+path tuples.
class Tinyapp
  def initialize
    @routes = {}
  end

  %i[get post put delete].each do |verb|
    define_method(verb) do |path, &block|
      @routes[[verb, path]] = block
    end
  end

  def call(env)
    method = env["REQUEST_METHOD"].downcase.to_sym
    handler = @routes[[method, env["PATH_INFO"]]]
    return [404, {}, ["not found"]] unless handler
    [200, { "content-type" => "text/plain" }, [handler.call.to_s]]
  end
end

app = Tinyapp.new
app.get "/" do
  "hello, world"
end
```

## Rust

```rust
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct Counter<K: Eq + std::hash::Hash + Clone> {
    counts: HashMap<K, usize>,
}

impl<K: Eq + std::hash::Hash + Clone> Counter<K> {
    pub fn new() -> Self {
        Self { counts: HashMap::new() }
    }

    pub fn bump(&mut self, key: K) -> usize {
        let entry = self.counts.entry(key).or_insert(0);
        *entry += 1;
        *entry
    }

    pub fn top(&self, n: usize) -> Vec<(K, usize)> {
        let mut sorted: Vec<_> = self.counts.iter().map(|(k, v)| (k.clone(), *v)).collect();
        sorted.sort_by(|a, b| b.1.cmp(&a.1));
        sorted.truncate(n);
        sorted
    }
}

fn main() {
    let mut c = Counter::new();
    for word in "the quick brown fox jumps over the lazy dog the".split_whitespace() {
        c.bump(word.to_string());
    }
    println!("{:?}", c.top(3));
}
```

## TOML

```toml
[package]
name        = "mdv"
version     = "0.2.0"
authors     = ["Josh Vanderberg <jvanderberg@gmail.com>"]
description = "A native macOS Markdown viewer."
license     = "MIT"
edition     = "2024"

[dependencies]
swift-markdown-ui  = { version = "2.4", features = ["full"] }
SwiftTreeSitter    = { version = "0.25" }

[features]
default = ["images", "live-reload"]
images       = []
live-reload  = []

[[bin]]
name = "mdv"
path = "src/main.swift"
```

## YAML

```yaml
# A GitHub Actions workflow for building and testing mdv on every push.
name: build

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    runs-on: macos-15
    timeout-minutes: 15
    strategy:
      matrix:
        config: [debug, release]
    steps:
      - uses: actions/checkout@v4
      - name: Show Xcode
        run: xcodebuild -version
      - name: Build (${{ matrix.config }})
        run: ./build.sh ${{ matrix.config }}
      - name: Smoke test the bundle
        run: |
          test -d build/mdv.app
          codesign -dv build/mdv.app
```
