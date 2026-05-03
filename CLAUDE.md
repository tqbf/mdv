# mdv

## SwiftUI

Don't write `@State` or `@Published` from a `.onChange(of: X)` when `X` is derived from state the view body writes during layout (e.g. via `onAppear` / `onDisappear`). That creates an infinite re-render loop and pegs the main thread.

If you need the value at navigation/action time, read the computed property directly. If you must mirror it, defer the write with `DispatchQueue.main.async`.

100% CPU with `sample <pid>` showing repeated `GraphHost.flushTransactions` frames is the signature.
