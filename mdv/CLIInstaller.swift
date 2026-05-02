import Foundation
import AppKit

// Installs /usr/local/bin/mdv as a symlink to the CLI helper bundled inside
// this .app (Contents/Resources/mdv). Mirrors what `make install-cli` does
// from the command line, but driven from a menu item so a downloaded .app
// can wire up the shell command without the user touching the Makefile.
//
// /usr/local/bin is root-owned on a stock macOS, so we try a plain symlink
// first (works on Homebrew-managed prefixes where the user owns the dir)
// and fall back to NSAppleScript's `with administrator privileges`, which
// pops the standard auth dialog. The app is unsandboxed (see
// mdv.entitlements), so this path is permitted.
enum CLIInstaller {
    static let destination = "/usr/local/bin/mdv"

    static func install() {
        guard let source = bundledScriptPath() else {
            alert(title: "CLI helper missing",
                  message: "The bundled mdv script wasn't found inside this build.",
                  style: .warning)
            return
        }

        if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: destination),
           resolved == source {
            alert(title: "Already installed",
                  message: "\(destination) already points to this app.",
                  style: .informational)
            return
        }

        if symlinkUnprivileged(source: source, destination: destination) {
            reportSuccess(source: source)
            return
        }

        switch symlinkWithAdminAuth(source: source, destination: destination) {
        case .success:
            reportSuccess(source: source)
        case .cancelled:
            break
        case .failed(let message):
            alert(title: "Install failed", message: message, style: .warning)
        }
    }

    private static func bundledScriptPath() -> String? {
        Bundle.main.url(forResource: "mdv", withExtension: nil)?.path
    }

    private static func symlinkUnprivileged(source: String, destination: String) -> Bool {
        let fm = FileManager.default
        let parent = (destination as NSString).deletingLastPathComponent
        do {
            if !fm.fileExists(atPath: parent) {
                try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            }
            // removeItem covers regular files and existing symlinks (including dangling ones).
            if fm.fileExists(atPath: destination)
                || (try? fm.destinationOfSymbolicLink(atPath: destination)) != nil {
                try fm.removeItem(atPath: destination)
            }
            try fm.createSymbolicLink(atPath: destination, withDestinationPath: source)
            return true
        } catch {
            return false
        }
    }

    private enum AuthResult {
        case success
        case cancelled
        case failed(String)
    }

    private static func symlinkWithAdminAuth(source: String, destination: String) -> AuthResult {
        let parent = (destination as NSString).deletingLastPathComponent
        let shell = "/bin/mkdir -p \(shellQuote(parent)) && /bin/ln -sf \(shellQuote(source)) \(shellQuote(destination))"
        // Embed the shell string inside an AppleScript string literal — escape
        // backslashes first, then double-quotes, in that order.
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"

        var errInfo: NSDictionary?
        NSAppleScript(source: appleScript)?.executeAndReturnError(&errInfo)
        guard let err = errInfo else { return .success }
        // -128 is the AppleScript "user cancelled" code from the auth dialog.
        if (err[NSAppleScript.errorNumber] as? Int) == -128 { return .cancelled }
        return .failed((err[NSAppleScript.errorMessage] as? String) ?? "Unknown error")
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func reportSuccess(source: String) {
        alert(title: "Command line tool installed",
              message: "\(destination) → \(source)\n\nYou can now run `mdv` from your terminal.",
              style: .informational)
    }

    private static func alert(title: String, message: String, style: NSAlert.Style) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.alertStyle = style
        a.runModal()
    }
}
