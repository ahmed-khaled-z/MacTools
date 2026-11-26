import Cocoa
import SwiftUI

// Shared helpers for every tool file. Keep tool files free of their own copies.

let home = NSHomeDirectory()
let shellEnv = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home, "LANG": "en_US.UTF-8"]

/// Run a zsh command synchronously. Call from a background queue / Task, never the main thread for slow commands.
@discardableResult
func sh(_ cmd: String) -> (code: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-c", cmd]
    p.environment = shellEnv
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

/// Async wrapper: runs `sh` off the main thread.
func shAsync(_ cmd: String) async -> (code: Int32, out: String) {
    await Task.detached { sh(cmd) }.value
}

/// Single-quote a string for safe use inside a zsh command.
func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

/// Human-readable size from kilobytes.
func human(kb: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(kb) * 1024, countStyle: .file) }

/// `du -sk` of a path in KB (0 if missing).
func sizeKB(_ path: String) -> Int {
    Int(sh("du -sk \(q(path)) 2>/dev/null | cut -f1").out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
}

func notify(_ title: String, _ msg: String) {
    let clean = { (s: String) in s.replacingOccurrences(of: "\"", with: "'") }
    sh("osascript -e \(q("display notification \"\(clean(msg))\" with title \"\(clean(title))\""))")
}

func copyToClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

// MARK: - Shared UI building blocks (use these so every tool looks the same)

/// A rounded card section inside a tool page.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
    }
}

/// A row with an icon, title, optional subtitle and a trailing accessory.
struct Row<Trailing: View>: View {
    var symbol: String
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// Shown while a tool is working.
struct Busy: View {
    var text: String
    var body: some View { HStack(spacing: 8) { ProgressView().controlSize(.small); Text(text).foregroundStyle(.secondary) } }
}
