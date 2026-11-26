import SwiftUI
import AppKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Shared bits

/// Sets a flag for ~1.2s (used for "اتنسخ ✓" confirmations).
@MainActor private func flash(_ flag: Binding<Bool>) {
    withAnimation { flag.wrappedValue = true }
    Task {
        try? await Task.sleep(for: .seconds(1.2))
        withAnimation { flag.wrappedValue = false }
    }
}

private struct CopyButton: View {
    let text: String
    @State private var done = false
    @State private var hover = false
    var body: some View {
        Button {
            copyToClipboard(text)
            flash($done)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: done ? "checkmark" : "doc.on.doc")
                if done { Text("اتنسخ ✓").font(.caption) }
            }
            .foregroundStyle(done ? Color.green : (hover ? Color.accentColor : Color.secondary))
        }
        .buttonStyle(.borderless)
        .onHover { hover = $0 }
    }
}

// MARK: - 1. Clipboard history

@MainActor
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()
    @Published var items: [String] = UserDefaults.standard.stringArray(forKey: "clipHistory") ?? []
    private var lastCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        if pb.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true { return }
        guard let s = pb.string(forType: .string),
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              s.count <= 10_000 else { return }
        items.removeAll { $0 == s }
        items.insert(s, at: 0)
        if items.count > 30 { items.removeLast(items.count - 30) }
        save()
    }

    func remove(_ s: String) { items.removeAll { $0 == s }; save() }
    func clear() { items = []; save() }
    private func save() { UserDefaults.standard.set(items, forKey: "clipHistory") }
}

private struct ClipRow: View {
    let text: String
    let onDelete: () -> Void
    @State private var copied = false
    @State private var hover = false

    private var looksLikeCode: Bool {
        text.hasPrefix("http") || text.contains("://") || text.contains("{") || text.contains(";")
            || text.contains("func ") || text.contains("=>") || text.contains("</")
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                copyToClipboard(text)
                flash($copied)
            } label: {
                HStack(spacing: 6) {
                    Text(text)
                        .font(looksLikeCode ? .system(.caption, design: .monospaced) : .callout)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if copied { Text("اتنسخ ✓").font(.caption).foregroundStyle(.green) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(hover ? Color.red : Color.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hover ? 0.08 : 0.03)))
        .onHover { hover = $0 }
    }
}

struct ClipboardView: View {
    @ObservedObject private var store = ClipboardStore.shared
    @State private var query = ""

    private var shown: [String] {
        query.isEmpty ? store.items : store.items.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("دوّر في اللي نسخته", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("\(store.items.count) عنصر").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        withAnimation { store.clear() }
                    } label: { Label("امسح الكل", systemImage: "trash") }
                        .disabled(store.items.isEmpty)
                }
            }
            Card {
                if shown.isEmpty {
                    Text(store.items.isEmpty ? "لسه مفيش حاجة اتنسخت" : "مفيش نتايج")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(shown, id: \.self) { s in
                        ClipRow(text: s) { withAnimation { store.remove(s) } }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .animation(.default, value: shown)
    }
}

// MARK: - 2. Network

struct NetworkView: View {
    @State private var localIP = "—"
    @State private var wifi = "—"
    @State private var publicIP = "—"
    @State private var running = false
    @State private var speed: (down: Double, up: Double, rpm: Int?)?
    @State private var speedError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                Row(symbol: "house", title: "IP المحلي", subtitle: localIP) {
                    if localIP != "—" { CopyButton(text: localIP) }
                }
                Row(symbol: "wifi", title: "الواي فاي", subtitle: wifi) {
                    if wifi != "—" { CopyButton(text: wifi) }
                }
                Row(symbol: "globe", title: "IP العام", subtitle: publicIP) {
                    if publicIP != "—" { CopyButton(text: publicIP) }
                }
                Button { Task { await refresh() } } label: { Label("حدّث", systemImage: "arrow.clockwise") }
            }
            Card {
                Button { Task { await runSpeedTest() } } label: {
                    Label("قيس السرعة", systemImage: "speedometer").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(running)
                if running {
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        let n = Int(ctx.date.timeIntervalSinceReferenceDate * 2) % 4
                        Busy(text: "بيقيس السرعة" + String(repeating: ".", count: n))
                    }
                } else if let speed {
                    Row(symbol: "arrow.down.circle", title: "تنزيل", subtitle: nil) {
                        Text(String(format: "%.0f Mbps", speed.down)).monospacedDigit().bold()
                    }
                    Row(symbol: "arrow.up.circle", title: "رفع", subtitle: nil) {
                        Text(String(format: "%.0f Mbps", speed.up)).monospacedDigit().bold()
                    }
                    if let rpm = speed.rpm {
                        Row(symbol: "timer", title: "الاستجابة", subtitle: nil) {
                            Text("\(rpm) RPM").monospacedDigit().bold()
                        }
                    }
                } else if let speedError {
                    Text(speedError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .animation(.default, value: running)
        .task { await refresh() }
    }

    private func refresh() async {
        var ip = await shAsync("ipconfig getifaddr en0").out.trimmingCharacters(in: .whitespacesAndNewlines)
        if ip.isEmpty { ip = await shAsync("ipconfig getifaddr en1").out.trimmingCharacters(in: .whitespacesAndNewlines) }
        localIP = ip.isEmpty ? "—" : ip

        let w = await shAsync("networksetup -getairportnetwork en0").out.trimmingCharacters(in: .whitespacesAndNewlines)
        if w.hasPrefix("Current Wi-Fi Network:"), let name = w.split(separator: ":", maxSplits: 1).last {
            let n = name.trimmingCharacters(in: .whitespaces)
            wifi = n.isEmpty ? "—" : n
        } else { wifi = "—" }

        if let url = URL(string: "https://api.ipify.org"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            publicIP = s
        } else { publicIP = "—" }
    }

    private func runSpeedTest() async {
        running = true; speed = nil; speedError = nil
        let out = await shAsync("networkQuality -c").out
        running = false
        if let a = out.firstIndex(of: "{"), let b = out.lastIndex(of: "}"),
           let obj = try? JSONSerialization.jsonObject(with: Data(out[a...b].utf8)) as? [String: Any],
           let dl = (obj["dl_throughput"] as? NSNumber)?.doubleValue,
           let ul = (obj["ul_throughput"] as? NSNumber)?.doubleValue {
            speed = (dl / 1_000_000, ul / 1_000_000, (obj["responsiveness"] as? NSNumber)?.intValue)
        } else {
            speedError = "القياس فشل، جرّب تاني"
        }
    }
}

// MARK: - 3. QR

/// Renders `text` as a crisp QR (with a white quiet zone) about `side` pixels wide.
private func makeQR(_ text: String, side: CGFloat = 660) -> NSImage? {
    let f = CIFilter.qrCodeGenerator()
    f.message = Data(text.utf8)
    f.correctionLevel = "M"
    guard let qr = f.outputImage else { return nil }
    let margin: CGFloat = 4
    let modules = qr.extent.width + margin * 2
    let scale = max(1, (side / modules).rounded(.down))
    let big = qr.samplingNearest()
        .transformed(by: CGAffineTransform(translationX: margin, y: margin))
        .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let rect = CGRect(x: 0, y: 0, width: modules * scale, height: modules * scale)
    let img = big.composited(over: CIImage(color: .white).cropped(to: rect)).cropped(to: rect)
    guard let cg = CIContext().createCGImage(img, from: rect) else { return nil }
    return NSImage(cgImage: cg, size: rect.size)
}

struct QRView: View {
    @State private var text = ""
    @State private var copied = false
    @State private var saved = false

    var body: some View {
        let image = text.isEmpty ? nil : makeQR(text)
        VStack(alignment: .leading, spacing: 12) {
            Card {
                TextField("اكتب نص أو لينك", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Button {
                    text = String((NSPasteboard.general.string(forType: .string) ?? "").prefix(1000))
                } label: { Label("هات من الحافظة", systemImage: "doc.on.clipboard") }
                    .buttonStyle(.borderless)
            }
            Card {
                if let image {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 220, height: 220)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity)
                    HStack {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([image])
                            flash($copied)
                        } label: { Label(copied ? "اتنسخ ✓" : "انسخ الصورة", systemImage: "doc.on.doc") }
                        Button {
                            save(image)
                        } label: { Label(saved ? "اتحفظ ✓" : "احفظ", systemImage: "square.and.arrow.down") }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("اكتب حاجة عشان يتعمل QR").foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            if text.isEmpty { text = String((NSPasteboard.general.string(forType: .string) ?? "").prefix(1000)) }
        }
    }

    private func save(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let path = "\(home)/Downloads/QR-\(stamp).png"
        if (try? png.write(to: URL(fileURLWithPath: path))) != nil {
            flash($saved)
            notify("QR اتحفظ", "Downloads/QR-\(stamp).png")
        } else {
            notify("QR", "معرفتش أحفظ الصورة")
        }
    }
}

// MARK: - 4. Toggles

private struct Tile: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let isToggle: Bool
}

struct TogglesView: View {
    private let tiles = [
        Tile(id: "dark", symbol: "moon.fill", title: "الوضع الداكن", isToggle: true),
        Tile(id: "desktop", symbol: "menubar.dock.rectangle", title: "إخفاء أيقونات الديسكتوب", isToggle: true),
        Tile(id: "hidden", symbol: "eye", title: "الملفات المخفية", isToggle: true),
        Tile(id: "eject", symbol: "eject.fill", title: "اطرد كل الهاردات", isToggle: false),
        Tile(id: "lock", symbol: "lock.fill", title: "قفل الشاشة", isToggle: false),
    ]
    @State private var on: [String: Bool] = [:]
    @State private var busy: String?
    @State private var hovered: String?

    var body: some View {
        Card {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(tiles) { t in tile(t) }
            }
        }
        .task { await refresh() }
    }

    private func tile(_ t: Tile) -> some View {
        let isOn = on[t.id] ?? false
        let tint: Color = t.isToggle && isOn ? .accentColor : .secondary
        return Button { Task { await tap(t) } } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: t.symbol).font(.title3).foregroundStyle(tint)
                    Spacer()
                    if busy == t.id { ProgressView().controlSize(.small) }
                }
                Text(t.title).font(.callout).lineLimit(2).multilineTextAlignment(.leading)
                Text(t.isToggle ? (isOn ? "شغال" : "مقفول") : "نفّذ")
                    .font(.caption).foregroundStyle(tint)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(t.isToggle && isOn ? Color.accentColor.opacity(0.18) : Color.primary.opacity(hovered == t.id ? 0.10 : 0.05)))
            .scaleEffect(hovered == t.id ? 1.02 : 1)
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .disabled(busy != nil)
        .onHover { hovered = $0 ? t.id : (hovered == t.id ? nil : hovered) }
    }

    private func refresh() async {
        let dark = await shAsync("defaults read -g AppleInterfaceStyle").out.trimmingCharacters(in: .whitespacesAndNewlines) == "Dark"
        let cd = await shAsync("defaults read com.apple.finder CreateDesktop").out.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sh_ = await shAsync("defaults read com.apple.finder AppleShowAllFiles").out.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        withAnimation {
            on["dark"] = dark
            on["desktop"] = (cd == "0" || cd == "false")   // on = icons hidden
            on["hidden"] = ["1", "true", "yes"].contains(sh_)
        }
    }

    private func tap(_ t: Tile) async {
        busy = t.id
        switch t.id {
        case "dark":
            _ = await shAsync("osascript -e 'tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode'")
        case "desktop":
            let hide = !(on["desktop"] ?? false)
            _ = await shAsync("defaults write com.apple.finder CreateDesktop -bool \(hide ? "false" : "true"); killall Finder")
        case "hidden":
            let show = !(on["hidden"] ?? false)
            _ = await shAsync("defaults write com.apple.finder AppleShowAllFiles -bool \(show ? "true" : "false"); killall Finder")
        case "eject":
            let r = await shAsync("osascript -e 'tell application \"Finder\" to eject (every disk whose ejectable is true)'")
            notify("اطرد الهاردات", r.code == 0 ? "تم" : "فشل: \(r.out.prefix(80))")
        case "lock":
            _ = await shAsync("pmset displaysleepnow")
        default: break
        }
        await refresh()
        busy = nil
    }
}

// MARK: - 5. Password

struct PasswordView: View {
    @State private var length = 20.0
    @State private var digits = true
    @State private var symbols = true
    @State private var upper = true
    @State private var noSimilar = false
    @State private var password = ""
    @State private var copied = false
    @State private var hover = false

    private static let symbolSet = Array("!@#$%^&*()-_=+[]{};:,.?")

    private var pools: [[Character]] {
        let similar: Set<Character> = noSimilar ? Set("0O1lI") : []
        var p = [Array("abcdefghijklmnopqrstuvwxyz")]
        if upper { p.append(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")) }
        if digits { p.append(Array("0123456789")) }
        if symbols { p.append(Self.symbolSet) }
        return p.map { $0.filter { !similar.contains($0) } }
    }

    private var bits: Double {
        let size = Set(pools.flatMap { $0 }).count
        return length * log2(Double(max(size, 2)))
    }

    private var strength: (label: String, color: Color) {
        switch bits {
        case ..<40: ("ضعيف", .red)
        case ..<60: ("متوسط", .orange)
        case ..<80: ("قوي", .green)
        default: ("قوي جدًا", .mint)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                Button {
                    copyToClipboard(password)
                    flash($copied)
                } label: {
                    VStack(spacing: 6) {
                        Text(password)
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .textSelection(.disabled)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Text(copied ? "اتنسخ ✓" : "دوس عشان تنسخ")
                            .font(.caption).foregroundStyle(copied ? Color.green : Color.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(hover ? 0.10 : 0.05)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hover = $0 }

                ProgressView(value: min(bits, 128), total: 128).tint(strength.color)
                HStack {
                    Text(strength.label).bold().foregroundStyle(strength.color)
                    Spacer()
                    Text("\(Int(bits)) bit").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Button { generate() } label: { Label("جديد", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
            }
            Card {
                HStack {
                    Text("الطول")
                    Spacer()
                    Text("\(Int(length))").monospacedDigit().bold()
                }
                Slider(value: $length, in: 8...64, step: 1)
                Toggle("أرقام", isOn: $digits)
                Toggle("رموز", isOn: $symbols)
                Toggle("حروف كبيرة", isOn: $upper)
                Toggle("تجنّب الحروف المتشابهة (0O1lI)", isOn: $noSimilar)
            }
        }
        .onAppear { if password.isEmpty { generate() } }
        .onChange(of: "\(length)\(digits)\(symbols)\(upper)\(noSimilar)") { generate() }
    }

    private func generate() {
        var rng = SystemRandomNumberGenerator()
        let p = pools
        let all = p.flatMap { $0 }
        var chars = p.compactMap { $0.randomElement(using: &rng) }   // one of each enabled class
        while chars.count < Int(length) { chars.append(all.randomElement(using: &rng)!) }
        password = String(chars.shuffled(using: &rng))
    }
}

// MARK: - 6. OCR

/// Interactive screen capture + Vision OCR. Runs blocking work, call off the main thread.
/// Returns nil when the user cancelled the selection.
private func captureAndRecognize(to path: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-i", "-x", path]
    guard (try? p.run()) != nil else { return nil }
    p.waitUntilExit()
    guard FileManager.default.fileExists(atPath: path) else { return nil }

    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.recognitionLanguages = ["ar-SA", "en-US"]
    req.usesLanguageCorrection = true
    try? VNImageRequestHandler(url: URL(fileURLWithPath: path)).perform([req])
    return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}

struct OCRView: View {
    @State private var text = ""
    @State private var thumb: NSImage?
    @State private var working = false
    @State private var empty = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                Button { Task { await grab() } } label: {
                    Label("حدد جزء من الشاشة", systemImage: "viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(working)
                if working { Busy(text: "بيقرا النص...") }
                if empty { Text("مفيش نص اتلقى في الصورة").font(.caption).foregroundStyle(.secondary) }
            }
            if let thumb {
                Card {
                    Image(nsImage: thumb).resizable().scaledToFit()
                        .frame(maxHeight: 120).clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity)
                }
                .transition(.opacity)
            }
            if !text.isEmpty {
                Card {
                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                    Button {
                        copyToClipboard(text)
                        flash($copied)
                    } label: { Label(copied ? "اتنسخ ✓" : "انسخ", systemImage: "doc.on.doc") }
                }
                .transition(.opacity)
            }
        }
        .animation(.default, value: text.isEmpty)
    }

    private func grab() async {
        working = true; empty = false
        let path = NSTemporaryDirectory() + "ocr-\(UUID().uuidString).png"
        NotificationCenter.default.post(name: .init("MacToolsClosePopover"), object: nil)
        try? await Task.sleep(for: .milliseconds(300))   // let the popover close before the selection UI appears

        let result = await Task.detached { captureAndRecognize(to: path) }.value
        let img = (try? Data(contentsOf: URL(fileURLWithPath: path))).flatMap { NSImage(data: $0) }
        try? FileManager.default.removeItem(atPath: path)
        working = false

        guard let result else { return }   // cancelled
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation {
            thumb = img
            text = trimmed
            empty = trimmed.isEmpty
        }
        guard !trimmed.isEmpty else { return }
        copyToClipboard(trimmed)
        flash($copied)
        let preview = String(trimmed.prefix(60))
        Task.detached { notify("النص اتنسخ", preview) }
    }
}
