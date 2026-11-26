import Cocoa
import SwiftUI

// MARK: - Ports

private struct PortItem: Identifiable, Hashable {
    let name: String
    let pid: Int
    let port: Int
    var id: String { "\(pid):\(port)" }
    var tag: String? {
        switch port {
        case 8081: return "Metro"
        case 19000...19006: return "Expo"
        case 5173: return "Vite"
        case 3000: return "Dev"
        case 8080: return "Dev"
        default: return nil
        }
    }
}

struct PortsView: View {
    @State private var items: [PortItem] = []
    @State private var loading = false
    @State private var failed: PortItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                HStack {
                    Text("البورتات المفتوحة").font(.headline)
                    Spacer()
                    Button { Task { await refresh() } } label: { Label("حدّث", systemImage: "arrow.clockwise") }
                        .disabled(loading)
                }
                if loading && items.isEmpty {
                    Busy(text: "بدوّر...")
                } else if items.isEmpty {
                    Text("مفيش بورتات مفتوحة دلوقتي").foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    Row(symbol: "network", title: item.name, subtitle: "PID \(item.pid)") {
                        HStack(spacing: 6) {
                            if let tag = item.tag {
                                Text(tag).font(.caption2).bold()
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                            }
                            Text(":\(String(item.port))").font(.system(.body, design: .monospaced))
                            Button("اقفل") { Task { await kill(item, force: false) } }
                                .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
        }
        .task { await refresh() }
        .alert("القفل العادي ما نفعش", isPresented: Binding(get: { failed != nil }, set: { if !$0 { failed = nil } })) {
            Button("اقفل بالعافية (kill -9)", role: .destructive) {
                if let f = failed { Task { await kill(f, force: true) } }
                failed = nil
            }
            Button("إلغاء", role: .cancel) { failed = nil }
        } message: {
            Text("\(failed?.name ?? "") (PID \(failed?.pid ?? 0)) لسه شغال. تجرب kill -9؟")
        }
    }

    private func refresh() async {
        loading = true
        let out = await shAsync("lsof -nP -iTCP -sTCP:LISTEN").out
        var seen = Set<String>()
        var list: [PortItem] = []
        for line in out.split(separator: "\n").dropFirst() {
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count >= 9, let pid = Int(f[1]) else { continue }
            // NAME is the field before "(LISTEN)"
            let nameIdx = f.last == "(LISTEN)" ? f.count - 2 : f.count - 1
            guard let port = Int(f[nameIdx].split(separator: ":").last ?? "") else { continue }
            let item = PortItem(name: String(f[0]).replacingOccurrences(of: "\\x20", with: " "), pid: pid, port: port)
            if seen.insert(item.id).inserted { list.append(item) }
        }
        withAnimation { items = list.sorted { $0.port < $1.port } }
        loading = false
    }

    private func kill(_ item: PortItem, force: Bool) async {
        let r = await shAsync("kill \(force ? "-9 " : "")\(item.pid)")
        if r.code != 0 && !force { failed = item; return }
        try? await Task.sleep(nanoseconds: 300_000_000)
        await refresh()
    }
}

// MARK: - node_modules / Pods

private struct DirItem: Identifiable {
    let path: String
    let kb: Int
    var id: String { path }
}

struct NodeModulesView: View {
    @State private var items: [DirItem] = []
    @State private var selected = Set<String>()
    @State private var scanning = false
    @State private var deleting = false
    @State private var scanned = false
    @State private var confirm = false

    private let root = home + "/projects"
    private var totalKB: Int { items.reduce(0) { $0 + $1.kb } }
    private var selectedItems: [DirItem] { items.filter { selected.contains($0.path) } }
    private var selectedKB: Int { selectedItems.reduce(0) { $0 + $1.kb } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                HStack {
                    Text(scanned ? "الإجمالي: \(human(kb: totalKB))" : "node_modules و Pods").font(.headline)
                    Spacer()
                    Button { Task { await scan() } } label: {
                        Label(scanned ? "اسكان تاني" : "اسكان", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent).disabled(scanning || deleting)
                }
                if scanning { Busy(text: "بدوّر في ~/projects...") }
                else if deleting { Busy(text: "بمسح...") }
                else if scanned && items.isEmpty { Text("مفيش حاجة تتمسح").foregroundStyle(.secondary) }
                else if !scanned { Text("دوس اسكان عشان يدوّر (ممكن ياخد وقت)").foregroundStyle(.secondary) }
            }
            if !items.isEmpty {
                Card {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { selected.contains(item.path) },
                                set: { on in
                                    withAnimation { if on { selected.insert(item.path) } else { selected.remove(item.path) } }
                                })).labelsHidden()
                            Text(rel(item.path)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(human(kb: item.kb)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .transition(.opacity)
                    }
                    Button { confirm = true } label: { Label("امسح المحدد", systemImage: "trash") }
                        .buttonStyle(.borderedProminent).tint(.red)
                        .disabled(selected.isEmpty || scanning || deleting)
                }
            }
        }
        .alert("تمسح \(selectedItems.count) فولدر؟", isPresented: $confirm) {
            Button("امسح", role: .destructive) { Task { await deleteSelected() } }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("هيتمسح \(human(kb: selectedKB)). تقدر ترجّعهم بـ npm install / pod install.")
        }
    }

    private func rel(_ p: String) -> String { p.hasPrefix(root + "/") ? String(p.dropFirst(root.count + 1)) : p }

    private func scan() async {
        scanning = true
        let found = await shAsync("find \(q(root)) \\( -name node_modules -o -name Pods \\) -type d -prune -maxdepth 6 2>/dev/null")
            .out.split(separator: "\n").map(String.init)
        var list: [DirItem] = []
        if !found.isEmpty {
            let out = await shAsync("du -sk " + found.map(q).joined(separator: " ") + " 2>/dev/null").out
            for line in out.split(separator: "\n") {
                let p = line.split(separator: "\t", maxSplits: 1)
                if p.count == 2, let kb = Int(p[0]) { list.append(DirItem(path: String(p[1]), kb: kb)) }
            }
        }
        withAnimation {
            items = list.sorted { $0.kb > $1.kb }
            selected = selected.intersection(Set(list.map(\.path)))
            scanned = true
        }
        scanning = false
    }

    private func deleteSelected() async {
        deleting = true
        let paths = selectedItems.map(\.path)
        let freed = selectedKB
        let cmd = paths.map { "rm -rf \(q($0))" }.joined(separator: "; ")
        await shAsync(cmd)
        deleting = false
        withAnimation { selected = [] }
        await scan()
        notify("DevTools", "اتحرر \(human(kb: freed))")
    }
}

// MARK: - Simulator / Xcode cleanup

struct SimulatorCleanView: View {
    private enum Action: String { case unavailable, deviceSupport, caches }

    private static let lib = home + "/Library/Developer"
    private let devices = lib + "/CoreSimulator/Devices"
    private let deviceSupport = lib + "/Xcode/iOS DeviceSupport"
    private let caches = lib + "/CoreSimulator/Caches"
    private let archives = lib + "/Xcode/Archives"

    @State private var sizes: [String: Int] = [:]
    @State private var measuring = false
    @State private var working = false
    @State private var pending: Action?
    @State private var freedText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                HStack {
                    Text("المساحات").font(.headline)
                    Spacer()
                    Button { Task { await measure() } } label: { Label("حدّث", systemImage: "arrow.clockwise") }
                        .disabled(measuring || working)
                }
                sizeRow("iphone", "Simulators (Devices)", devices)
                sizeRow("cable.connector", "iOS DeviceSupport", deviceSupport)
                sizeRow("memorychip", "كاش Simulator", caches)
                sizeRow("archivebox", "Archives", archives) {
                    Button("افتح في Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: archives)) }
                        .controlSize(.small)
                }
                if measuring { Busy(text: "بحسب المساحات...") }
            }
            Card {
                Text("تنضيف").font(.headline)
                if working { Busy(text: "بنضّف...") }
                if let freedText {
                    Label(freedText, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        .transition(.opacity)
                }
                actionButton("امسح الـ simulators المش متاحة", "trash.slash", .unavailable)
                actionButton("امسح iOS DeviceSupport", "trash", .deviceSupport)
                actionButton("امسح كاش Simulator", "trash", .caches)
            }
        }
        .task { await measure() }
        .alert("متأكد؟", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("امسح", role: .destructive) { if let a = pending { Task { await run(a) } }; pending = nil }
            Button("إلغاء", role: .cancel) { pending = nil }
        } message: {
            Text(message(pending))
        }
    }

    private func message(_ a: Action?) -> String {
        switch a {
        case .unavailable: return "هيتمسح أي simulator مش متاح (runtimes قديمة)."
        case .deviceSupport: return "هيتمسح محتوى iOS DeviceSupport. Xcode هيرجّعه لما توصّل جهاز."
        case .caches: return "هيتمسح كاش الـ Simulator. بيتبني تاني لوحده."
        case nil: return ""
        }
    }

    private func sizeRow<T: View>(_ symbol: String, _ title: String, _ path: String, @ViewBuilder trailing: () -> T) -> some View {
        Row(symbol: symbol, title: title) {
            HStack(spacing: 8) {
                Text(sizes[path].map { human(kb: $0) } ?? "—").foregroundStyle(.secondary).monospacedDigit()
                trailing()
            }
        }
    }

    private func sizeRow(_ symbol: String, _ title: String, _ path: String) -> some View {
        sizeRow(symbol, title, path) { EmptyView() }
    }

    private func actionButton(_ title: String, _ symbol: String, _ a: Action) -> some View {
        Button { pending = a } label: { Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading) }
            .buttonStyle(.borderedProminent).disabled(working || measuring)
    }

    private func measure() async {
        measuring = true
        let paths = [devices, deviceSupport, caches, archives]
        let result = await Task.detached { Dictionary(uniqueKeysWithValues: paths.map { ($0, sizeKB($0)) }) }.value
        withAnimation { sizes = result }
        measuring = false
    }

    private func run(_ a: Action) async {
        working = true
        let before = sizes.values.reduce(0, +)
        switch a {
        case .unavailable: await shAsync("xcrun simctl delete unavailable")
        case .deviceSupport: await shAsync("find \(q(deviceSupport)) -mindepth 1 -maxdepth 1 -exec rm -rf {} +")
        case .caches: await shAsync("find \(q(caches)) -mindepth 1 -maxdepth 1 -exec rm -rf {} +")
        }
        await measure()
        let freed = max(0, before - sizes.values.reduce(0, +))
        withAnimation { freedText = "اتحرر \(human(kb: freed))" }
        working = false
    }
}

// MARK: - Keep awake

@MainActor
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake()
    @Published var isOn = false
    @Published var endsAt: Date?
    private var proc: Process?

    func start(minutes: Int?) {
        stop()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-dimsu"] + (minutes.map { ["-t", String($0 * 60)] } ?? [])
        p.terminationHandler = { [weak self] done in
            DispatchQueue.main.async {
                // ignore exits of a process we already replaced
                guard let self, self.proc === done else { return }
                self.proc = nil
                self.isOn = false
                self.endsAt = nil
            }
        }
        do { try p.run() } catch { return }
        proc = p
        isOn = true
        endsAt = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
    }

    func stop() {
        let p = proc
        proc = nil
        p?.terminate()
        isOn = false
        endsAt = nil
    }
}

struct KeepAwakeView: View {
    @ObservedObject private var ka = KeepAwake.shared
    @State private var minutes: Int? = 60

    private let options: [(String, Int?)] = [("30 دقيقة", 30), ("ساعة", 60), ("ساعتين", 120), ("٤ ساعات", 240), ("لحد ما اقفله", nil)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                Button {
                    withAnimation { if ka.isOn { ka.stop() } else { ka.start(minutes: minutes) } }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "cup.and.saucer.fill").font(.system(size: 44))
                        Text(ka.isOn ? "الماك صاحي" : "دوس عشان الماك يفضل صاحي").font(.headline)
                        remaining
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .foregroundStyle(ka.isOn ? Color.white : Color.primary)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ka.isOn ? Color.orange : Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            Card {
                Text("المدة").font(.headline)
                HStack(spacing: 6) {
                    ForEach(options, id: \.0) { title, m in
                        Button(title) {
                            minutes = m
                            if ka.isOn { withAnimation { ka.start(minutes: m) } }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .tint(minutes == m ? .orange : .secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var remaining: some View {
        if ka.isOn, let end = ka.endsAt {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let s = max(0, Int(end.timeIntervalSince(ctx.date)))
                Text(String(format: "فاضل %d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60))
                    .monospacedDigit()
            }
        } else if ka.isOn {
            Text("لحد ما تقفله")
        }
    }
}
