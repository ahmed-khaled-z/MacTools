import Cocoa
import SwiftUI
import Combine

// MARK: - Tool registry

enum Tool: String, CaseIterable, Identifiable {
    case clean, download, ports, nodeModules, simulator, keepAwake, ocr, clipboard, network, qr, toggles, password
    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: "تنظيف المساحة"
        case .download: "تحميل فيديو / صوت"
        case .ports: "البورتات"
        case .nodeModules: "صياد node_modules"
        case .simulator: "تنظيف Simulator"
        case .keepAwake: "منع النوم"
        case .ocr: "نص من الشاشة"
        case .clipboard: "سجل الحافظة"
        case .network: "الشبكة"
        case .qr: "QR Code"
        case .toggles: "مفاتيح سريعة"
        case .password: "باسوردات"
        }
    }
    var symbol: String {
        switch self {
        case .clean: "sparkles"
        case .download: "arrow.down.circle.fill"
        case .ports: "network.badge.shield.half.filled"
        case .nodeModules: "shippingbox.fill"
        case .simulator: "iphone.gen3"
        case .keepAwake: "cup.and.saucer.fill"
        case .ocr: "text.viewfinder"
        case .clipboard: "doc.on.clipboard.fill"
        case .network: "wifi"
        case .qr: "qrcode"
        case .toggles: "switch.2"
        case .password: "key.fill"
        }
    }
    var color: Color {
        switch self {
        case .clean: .mint
        case .download: .red
        case .ports: .orange
        case .nodeModules: .green
        case .simulator: .blue
        case .keepAwake: .brown
        case .ocr: .purple
        case .clipboard: .indigo
        case .network: .cyan
        case .qr: .gray
        case .toggles: .pink
        case .password: .yellow
        }
    }
    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .clean: CleanView()
        case .download: DownloadView()
        case .ports: PortsView()
        case .nodeModules: NodeModulesView()
        case .simulator: SimulatorCleanView()
        case .keepAwake: KeepAwakeView()
        case .ocr: OCRView()
        case .clipboard: ClipboardView()
        case .network: NetworkView()
        case .qr: QRView()
        case .toggles: TogglesView()
        case .password: PasswordView()
        }
    }
}

let sections: [(String, [Tool])] = [
    ("المساحة والتحميل", [.clean, .download, .ocr]),
    ("البرمجة", [.ports, .nodeModules, .simulator, .keepAwake]),
    ("يومي", [.clipboard, .network, .qr, .toggles, .password]),
]

// MARK: - Root

struct RootView: View {
    @State private var tool: Tool?
    var body: some View {
        VStack(spacing: 0) {
            if let tool {
                ToolPage(tool: tool) { withAnimation(.snappy) { self.tool = nil } }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                HomeView { t in withAnimation(.snappy) { tool = t } }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: 420, height: 540)
        .environment(\.layoutDirection, .rightToLeft)
        .onReceive(NotificationCenter.default.publisher(for: .init("MacToolsOpenTool"))) { n in
            tool = (n.object as? String).flatMap(Tool.init(rawValue:))
        }
    }
}

struct HomeView: View {
    var open: (Tool) -> Void
    @State private var free: Int64 = 0
    @State private var total: Int64 = 1

    var body: some View {
        VStack(spacing: 0) {
            // Header with live disk usage
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "wrench.and.screwdriver.fill").font(.title2).foregroundStyle(.tint)
                    Text("MacTools").font(.title2.bold())
                    Spacer()
                    Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                        .buttonStyle(.borderless).help("خروج")
                }
                let used = Double(total - free) / Double(total)
                ProgressView(value: used).tint(used > 0.9 ? .red : used > 0.75 ? .orange : .green)
                Text("فاضي \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) من \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.ultraThinMaterial)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections, id: \.0) { name, tools in
                        Text(name).font(.subheadline.bold()).foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(tools) { t in HomeTile(tool: t) { open(t) } }
                        }
                    }
                }
                .padding(16)
            }
        }
        .onAppear(perform: readDisk)
    }

    func readDisk() {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        free = v?.volumeAvailableCapacityForImportantUsage ?? 0
        total = Int64(v?.volumeTotalCapacity ?? 1)
    }
}

struct HomeTile: View {
    var tool: Tool
    var action: () -> Void
    @State private var hover = false
    @ObservedObject private var awake = KeepAwake.shared

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 11).fill(tool.color.gradient))
                    if tool == .keepAwake && awake.isOn {
                        Circle().fill(.green).frame(width: 10, height: 10).offset(x: 3, y: -3)
                    }
                }
                Text(tool.title).font(.caption).multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 86)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(hover ? 0.09 : 0.04)))
            .scaleEffect(hover ? 1.04 : 1)
            .animation(.spring(duration: 0.25), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ToolPage: View {
    var tool: Tool
    var back: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: back) { Image(systemName: "chevron.right").font(.headline) }
                    .buttonStyle(.borderless).keyboardShortcut(.cancelAction)
                Image(systemName: tool.symbol).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(tool.color.gradient))
                Text(tool.title).font(.headline)
                Spacer()
            }
            .padding(14)
            .background(.ultraThinMaterial)
            ScrollView { tool.view.padding(16) }
        }
    }
}

// MARK: - Cleaner

struct CleanTarget: Identifiable {
    let id: String   // path
    let name: String
    var kb = 0
    var on = true
}

struct CleanView: View {
    @State private var targets: [CleanTarget] = [
        .init(id: "\(home)/.Trash", name: "سلة المهملات"),
        .init(id: "\(home)/Library/Caches", name: "كاش التطبيقات"),
        .init(id: "\(home)/Library/Logs", name: "ملفات اللوج"),
        .init(id: "\(home)/Library/Developer/Xcode/DerivedData", name: "Xcode DerivedData"),
        .init(id: "\(home)/.npm/_cacache", name: "كاش npm"),
        .init(id: "\(home)/Library/Caches/Yarn", name: "كاش Yarn"),
    ]
    @State private var brew = true
    @State private var scanning = true
    @State private var working = false
    @State private var confirm = false
    @State private var result: String?

    var selectedKB: Int { targets.filter(\.on).map(\.kb).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                HStack(alignment: .firstTextBaseline) {
                    Text(scanning ? "…" : human(kb: selectedKB)).font(.system(size: 34, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("هتتمسح").foregroundStyle(.secondary)
                }
                if let result { Label(result, systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
            }
            Card {
                if scanning { Busy(text: "بحسب الأحجام…") }
                ForEach($targets) { $t in
                    Row(symbol: "folder.fill", title: t.name, subtitle: human(kb: t.kb)) {
                        Toggle("", isOn: $t.on).toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                    .opacity(t.kb == 0 && !scanning ? 0.5 : 1)
                }
                Divider()
                Row(symbol: "mug.fill", title: "brew cleanup", subtitle: "نسخ Homebrew القديمة") {
                    Toggle("", isOn: $brew).toggleStyle(.switch).controlSize(.small).labelsHidden()
                }
            }
            HStack {
                Button { confirm = true } label: {
                    Label(working ? "بمسح…" : "امسح", systemImage: "trash.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(.mint)
                .disabled(scanning || working || (selectedKB == 0 && !brew))
                Button { Task { await scan() } } label: { Image(systemName: "arrow.clockwise") }
                    .controlSize(.large).disabled(scanning || working)
            }
            Text("بيمسح المحتوى بس، الفولدرات نفسها بتفضل. المسح نهائي (مش بيروح سلة المهملات).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await scan() }
        .alert("تمسح \(human(kb: selectedKB))؟", isPresented: $confirm) {
            Button("امسح", role: .destructive) { Task { await clean() } }
            Button("إلغاء", role: .cancel) {}
        } message: { Text("الملفات دي هتتمسح نهائيًا.") }
    }

    func scan() async {
        scanning = true
        for i in targets.indices {
            let path = targets[i].id
            let kb = await Task.detached { sizeKB(path) }.value
            withAnimation { targets[i].kb = kb }
        }
        scanning = false
    }

    func freeKB() async -> Int {
        Int(await shAsync("df -k ~ | tail -1 | awk '{print $4}'").out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func clean() async {
        working = true
        let before = await freeKB()
        for t in targets where t.on && t.kb > 0 {
            await shAsync("find \(q(t.id)) -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null")
        }
        if brew { await shAsync("brew cleanup -s --prune=all") }
        let freed = max(await freeKB() - before, 0)
        withAnimation { result = "اتوفر \(human(kb: freed))" }
        notify("تم التنظيف", "اتوفر \(human(kb: freed))")
        working = false
        await scan()
    }
}

// MARK: - Downloader (state lives in a singleton so it survives page switches)

@MainActor
final class Downloader: ObservableObject {
    static let shared = Downloader()
    struct Done: Identifiable { let id = UUID(); let path: String }

    @Published var running = false
    @Published var progress: Double = 0
    @Published var status = ""
    @Published var history: [Done] = []
    private var process: Process?

    func start(url: String, audio: Bool, quality: String) {
        guard !running else { return }
        let fmt: [String] = audio
            ? ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
            : ["-f", quality == "best" ? "bv*+ba/b" : "bv*[height<=\(quality)]+ba/b[height<=\(quality)]", "--merge-output-format", "mp4"]
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env") // finds yt-dlp via shellEnv PATH (Apple Silicon + Intel brew)
        p.arguments = ["yt-dlp"] + fmt + ["--no-playlist", "--newline", "--progress",
                             "--print", "after_move:filepath",
                             "-o", "\(home)/Downloads/%(title).80s.%(ext)s", url]
        p.environment = shellEnv
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        var lastError = ""
        var file: String?
        pipe.fileHandleForReading.readabilityHandler = { h in
            guard let s = String(data: h.availableData, encoding: .utf8), !s.isEmpty else { return }
            for line in s.split(whereSeparator: \.isNewline).map(String.init) {
                if line.hasPrefix("/") { file = line; continue }
                if line.contains("ERROR") { lastError = line }
                let pct = line.range(of: #"(\d+(\.\d+)?)%"#, options: .regularExpression).flatMap { Double(line[$0].dropLast()) }
                Task { @MainActor in
                    if let pct { self.progress = pct / 100; self.status = "بيحمّل…" }
                    else if line.contains("Merger") || line.contains("ExtractAudio") { self.status = "بيجهز الملف…" }
                }
            }
        }
        p.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let ok = proc.terminationStatus == 0
            Task { @MainActor in
                self.running = false
                if ok, let file {
                    self.progress = 1
                    self.status = "خلص ✓"
                    withAnimation { self.history.insert(.init(path: file), at: 0) }
                    notify("خلص التحميل ✅", (file as NSString).lastPathComponent)
                } else if proc.terminationReason == .uncaughtSignal {
                    self.status = "اتلغى"
                } else {
                    self.status = lastError.isEmpty ? "فشل التحميل" : lastError
                    notify("فشل التحميل ❌", self.status)
                }
            }
        }
        do {
            try p.run()
            process = p
            running = true
            progress = 0
            status = "بيبدأ…"
        } catch {
            status = "yt-dlp مش لاقيه — brew install yt-dlp"
        }
    }

    func cancel() { process?.terminate() }
}

struct DownloadView: View {
    @ObservedObject private var dl = Downloader.shared
    @State private var url = ""
    @State private var audio = false
    @State private var quality = "best"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                HStack {
                    TextField("حط اللينك هنا…", text: $url).textFieldStyle(.roundedBorder)
                        .environment(\.layoutDirection, .leftToRight)
                    Button { url = NSPasteboard.general.string(forType: .string) ?? url } label: {
                        Image(systemName: "doc.on.clipboard")
                    }.help("الصق")
                }
                Picker("", selection: $audio) {
                    Label("فيديو", systemImage: "film").tag(false)
                    Label("صوت MP3", systemImage: "music.note").tag(true)
                }.pickerStyle(.segmented).labelsHidden()
                if !audio {
                    Picker("الجودة", selection: $quality) {
                        Text("أعلى جودة").tag("best")
                        Text("1080p").tag("1080")
                        Text("720p").tag("720")
                        Text("480p").tag("480")
                    }.pickerStyle(.menu)
                }
                Text("يوتيوب · تيك توك · إنستجرام · فيسبوك · X وغيرهم").font(.caption).foregroundStyle(.secondary)
            }

            if dl.running || !dl.status.isEmpty {
                Card {
                    ProgressView(value: dl.progress).tint(.red).animation(.linear, value: dl.progress)
                    HStack {
                        Text(dl.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                        Text("\(Int(dl.progress * 100))%").font(.caption.monospacedDigit())
                    }
                }
            }

            if dl.running {
                Button(role: .destructive) { dl.cancel() } label: { Label("إلغاء", systemImage: "xmark").frame(maxWidth: .infinity) }
                    .controlSize(.large)
            } else {
                Button { dl.start(url: url.trimmingCharacters(in: .whitespacesAndNewlines), audio: audio, quality: quality) } label: {
                    Label("حمّل", systemImage: "arrow.down").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(.red)
                .disabled(!url.hasPrefix("http"))
            }

            if !dl.history.isEmpty {
                Card {
                    Text("اتحمّل").font(.subheadline.bold())
                    ForEach(dl.history) { d in
                        Row(symbol: d.path.hasSuffix(".mp3") ? "music.note" : "film", title: (d.path as NSString).lastPathComponent) {
                            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: d.path)]) } label: {
                                Image(systemName: "magnifyingglass")
                            }.buttonStyle(.borderless).help("اعرضه في Finder")
                        }
                    }
                }
            }
        }
        .onAppear {
            if url.isEmpty, let c = NSPasteboard.general.string(forType: .string), c.hasPrefix("http") { url = c }
        }
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var item: NSStatusItem!
    let popover = NSPopover()
    var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ n: Notification) {
        ClipboardStore.shared.start()

        popover.behavior = .transient
        popover.delegate = self
        // Fixed size: letting SwiftUI resize the popover after it opens makes it jump/clip off-screen.
        let hc = NSHostingController(rootView: RootView())
        hc.sizingOptions = []
        hc.view.frame = NSRect(x: 0, y: 0, width: 420, height: 540)
        popover.contentViewController = hc
        popover.contentSize = NSSize(width: 420, height: 540)
        popover.animates = false

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.action = #selector(toggle)
        item.button?.target = self
        setIcon(awake: false)

        KeepAwake.shared.$isOn.receive(on: RunLoop.main).sink { [weak self] on in self?.setIcon(awake: on) }.store(in: &bag)
        NotificationCenter.default.publisher(for: .init("MacToolsClosePopover"))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.popover.performClose(nil) }.store(in: &bag)
        // Debug: `--snapshot <tool|home> <out.png>` renders the panel offscreen and quits.
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--snapshot"), i + 2 < a.count { snapshot(tool: a[i + 1], to: a[i + 2]) }
        // Debug: `--popover <out.png>` opens the real popover, captures its window, prints frames.
        if let i = a.firstIndex(of: "--popover"), i + 1 < a.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.toggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    let w = self.popover.contentViewController?.view.window
                    print("button:", self.item.button?.window?.frame ?? .zero, "popover:", w?.frame ?? .zero, "shown:", self.popover.isShown)
                    if let w { sh("screencapture -x -l \(w.windowNumber) \(q(a[i + 1]))") }
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func snapshot(tool: String, to path: String) {
        let win = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 420, height: 540), styleMask: .borderless, backing: .buffered, defer: false)
        win.contentViewController = popover.contentViewController
        win.backgroundColor = .windowBackgroundColor
        win.level = .floating
        win.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NotificationCenter.default.post(name: .init("MacToolsOpenTool"), object: tool)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            sh("screencapture -x -o -l \(win.windowNumber) \(q(path))")
            NSApp.terminate(nil)
        }
    }

    func setIcon(awake: Bool) {
        item.button?.image = NSImage(systemSymbolName: awake ? "cup.and.saucer.fill" : "wrench.and.screwdriver",
                                     accessibilityDescription: "MacTools")
    }

    /// Invisible 1pt window used as the popover anchor when the real icon is off-screen
    /// (hidden behind the notch, or clicked through a menu-bar manager like Ice/Bartender).
    var anchor: NSWindow?

    @objc func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        NSApp.activate(ignoringOtherApps: true)
        guard let button = item.button else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        if let bw = button.window, screen.frame.contains(bw.frame) {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        } else {
            anchor?.close()
            let x = min(max(mouse.x, screen.visibleFrame.minX + 230), screen.visibleFrame.maxX - 230)
            let w = NSWindow(contentRect: NSRect(x: x, y: screen.visibleFrame.maxY - 1, width: 1, height: 1),
                             styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.backgroundColor = .clear
            w.level = .statusBar
            w.orderFrontRegardless()
            anchor = w
            popover.show(relativeTo: w.contentView!.bounds, of: w.contentView!, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ n: Notification) { anchor?.close(); anchor = nil }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
