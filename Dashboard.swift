import Cocoa
import SwiftUI
import Combine
import Darwin

// MARK: - Tabs

enum AppTab: Hashable { case home, tools }

struct TabBar: View {
    @Binding var tab: AppTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            item(.home, "الرئيسية", "house.fill")
            item(.tools, "الأدوات", "square.grid.2x2.fill")
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func item(_ t: AppTab, _ title: String, _ symbol: String) -> some View {
        Button {
            withAnimation(.snappy) { tab = t }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(tab == t ? Color.accentColor : Color.secondary)
            .background {
                if tab == t {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Activity (persisted)

@MainActor
final class ActivityStats: ObservableObject {
    static let shared = ActivityStats()
    @Published private(set) var bytesFreed: Int64
    @Published private(set) var downloadDates: [Date]

    private static let freedKey = "mt.bytesFreed"
    private static let dlKey = "mt.downloads"

    private init() {
        bytesFreed = (UserDefaults.standard.object(forKey: Self.freedKey) as? NSNumber)?.int64Value ?? 0
        let raw = UserDefaults.standard.array(forKey: Self.dlKey) as? [Double] ?? []
        downloadDates = raw.map { Date(timeIntervalSince1970: $0) }
    }

    func recordFreed(kb: Int) {
        guard kb > 0 else { return }
        bytesFreed += Int64(kb) * 1024
        UserDefaults.standard.set(NSNumber(value: bytesFreed), forKey: Self.freedKey)
    }

    func recordDownload(_ date: Date = .now) {
        downloadDates.append(date)
        UserDefaults.standard.set(downloadDates.map(\.timeIntervalSince1970), forKey: Self.dlKey)
    }

    var downloadsThisWeek: Int {
        let cut = Date().addingTimeInterval(-7 * 24 * 3600)
        return downloadDates.filter { $0 >= cut }.count
    }
}

// MARK: - Reclaimable space (launch + every 30 min)

@MainActor
final class ReclaimStore: ObservableObject {
    static let shared = ReclaimStore()
    @Published private(set) var kb: Int
    @Published private(set) var at: Date?
    private var timer: Timer?
    private var task: Task<Void, Never>?

    private static let kbKey = "mt.reclaimKB"
    private static let atKey = "mt.reclaimAt"

    private init() {
        let stamp = UserDefaults.standard.double(forKey: Self.atKey)
        kb = UserDefaults.standard.integer(forKey: Self.kbKey)
        at = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    func start() {
        guard timer == nil else { return }
        kick()
        let t = Timer(timeInterval: 30 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { ReclaimStore.shared.kick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func kick() {
        guard task == nil else { return }
        task = Task {
            let value = await Task.detached { Self.measure() }.value
            self.kb = value
            let now = Date()
            self.at = now
            UserDefaults.standard.set(value, forKey: Self.kbKey)
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.atKey)
            self.task = nil
        }
    }

    /// Cleaner targets plus node_modules/Pods. A path inside another one is counted once
    /// (Yarn's cache lives inside ~/Library/Caches).
    nonisolated static func measure() -> Int {
        let fixed = [
            "\(home)/.Trash",
            "\(home)/Library/Caches",
            "\(home)/Library/Logs",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/.npm/_cacache",
            "\(home)/Library/Caches/Yarn",
        ]
        let root = home + "/projects"
        let found = sh("find \(q(root)) \\( -name node_modules -o -name Pods \\) -type d -prune -maxdepth 6 2>/dev/null").out
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return duSum(deduped(fixed + found))
    }

    nonisolated private static func deduped(_ paths: [String]) -> [String] {
        var kept: [String] = []
        for p in paths.sorted() {
            if kept.contains(where: { p.hasPrefix($0 + "/") }) { continue }
            kept.append(p)
        }
        return kept
    }

    nonisolated private static func duSum(_ paths: [String]) -> Int {
        var total = 0
        var i = 0
        while i < paths.count {
            let end = min(i + 40, paths.count)
            let slice = paths[i..<end]
            i = end
            let out = sh("du -sk " + slice.map(q).joined(separator: " ") + " 2>/dev/null").out
            for line in out.split(separator: "\n") {
                if let kb = Int(line.split(separator: "\t", maxSplits: 1).first ?? "") { total += kb }
            }
        }
        return total
    }
}

func reclaimAgo(_ date: Date) -> String {
    let s = max(0, Int(Date().timeIntervalSince(date)))
    if s < 60 { return "اتحدّث دلوقتي" }
    let m = s / 60
    if m == 1 { return "اتحدّث من دقيقة" }
    if m == 2 { return "اتحدّث من دقيقتين" }
    if m < 60 { return "اتحدّث من \(m) دقيقة" }
    let h = m / 60
    if h == 1 { return "اتحدّث من ساعة" }
    if h == 2 { return "اتحدّث من ساعتين" }
    if h < 24 { return "اتحدّث من \(h) ساعات" }
    let d = h / 24
    return d == 1 ? "اتحدّث من يوم" : "اتحدّث من \(d) يوم"
}

// MARK: - Live stats, dev ports, git

struct NetSnapshot: Equatable {
    var ssid = "—"
    var online = false
    var ms: Int?
}

struct RepoChange: Identifiable, Equatable {
    let path: String
    let dirty: Bool
    let unpushed: Bool
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

struct CPUTicks {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64
    var busy: UInt64 { user &+ system &+ nice }
    var total: UInt64 { busy &+ idle }
}

enum HogKind: Hashable { case cpu, ram }

struct ProcRow {
    var pid: Int32
    var ppid: Int32
    var cpu: Double
    var rssKB: Int64
    var comm: String
}

struct Hog: Identifiable {
    let id: String
    let name: String
    var cpu: Double
    var rssKB: Int64
    let icon: NSImage?
    let app: NSRunningApplication?
    let canQuit: Bool
}

@MainActor
final class DashboardModel: ObservableObject {
    static let shared = DashboardModel()

    @Published var cpu: Double?
    @Published var cpuHist: [Double] = []
    @Published var ram: Double?
    @Published var diskFree: Int64 = 0
    @Published var diskTotal: Int64 = 1
    @Published var net = NetSnapshot()
    @Published var devPorts: [PortItem] = []
    @Published var git: [RepoChange]?
    @Published var hogs: [Hog] = []
    @Published var hogsReady = false

    private var popoverOn = false
    private var dashOn = false
    private var timer: Timer?
    private var prevTicks: CPUTicks?
    private var netBusy = false
    private var hogBusy = false
    private var portGen = 0
    private var gitBusy = false
    private var bag = Set<AnyCancellable>()

    private init() {
        Self.checkParser()
        let nc = NotificationCenter.default
        nc.publisher(for: .init("MacToolsPopoverDidShow"))
            .receive(on: RunLoop.main)
            .sink { _ in MainActor.assumeIsolated { DashboardModel.shared.setPopover(true) } }
            .store(in: &bag)
        nc.publisher(for: .init("MacToolsPopoverDidClose"))
            .receive(on: RunLoop.main)
            .sink { _ in MainActor.assumeIsolated { DashboardModel.shared.setPopover(false) } }
            .store(in: &bag)
    }

    func setPopover(_ on: Bool) {
        let opened = on && !popoverOn
        popoverOn = on
        syncTimer()
        if opened {
            refreshPorts()
            refreshGit()
        }
    }

    func setDashboard(_ on: Bool) {
        dashOn = on
        syncTimer()
    }

    private func syncTimer() {
        let want = popoverOn && dashOn
        if want, timer == nil {
            tick()
            let t = Timer(timeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated { DashboardModel.shared.tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !want, let t = timer {
            t.invalidate()
            timer = nil
        }
    }

    private func tick() {
        if let now = Self.readTicks() {
            if let prev = prevTicks, now.total >= prev.total {
                let dt = now.total - prev.total
                if dt > 0 {
                    let pct = min(100, max(0, Double(now.busy - prev.busy) / Double(dt) * 100))
                    withAnimation(.snappy) {
                        cpu = pct
                        cpuHist.append(pct)
                        if cpuHist.count > 30 { cpuHist.removeFirst(cpuHist.count - 30) }
                    }
                }
            }
            prevTicks = now
        }
        let ramNow = Self.readRAM()
        let disk = Self.readDisk()
        withAnimation(.snappy) {
            ram = ramNow
            diskFree = disk.free
            diskTotal = disk.total
        }
        refreshHogs()
        guard !netBusy else { return }
        netBusy = true
        Task {
            let info = await Task.detached { Self.probeNet() }.value
            withAnimation(.snappy) { self.net = info }
            self.netBusy = false
        }
    }

    private func refreshHogs() {
        guard !hogBusy else { return }
        hogBusy = true
        Task {
            let rows = await Task.detached { Self.readProcs() }.value
            withAnimation(.snappy) {
                self.hogs = Self.groupHogs(rows)
                self.hogsReady = true
            }
            self.hogBusy = false
        }
    }

    func refreshPorts() {
        portGen += 1
        let gen = portGen
        Task {
            let all = await listeningPorts()
            guard gen == self.portGen else { return }
            withAnimation { self.devPorts = all.filter { Self.isDashboardDev($0) } }
        }
    }

    func kill(_ item: PortItem) async {
        _ = await shAsync("kill \(item.pid)")
        try? await Task.sleep(nanoseconds: 300_000_000)
        refreshPorts()
    }

    func refreshGit() {
        guard !gitBusy else { return }
        gitBusy = true
        Task {
            let list = await Task.detached { Self.scanGit() }.value
            withAnimation { self.git = list }
            self.gitBusy = false
        }
    }

    static func isDevPort(_ port: Int) -> Bool {
        (3000...3999).contains(port) || port == 4200 || (5173...5174).contains(port)
            || (8000...8099).contains(port) || (19000...19006).contains(port)
    }

    /// lsof keeps 9 characters of the command, so "ControlCenter" arrives as "ControlCe".
    static func isDashboardDev(_ item: PortItem) -> Bool {
        guard isDevPort(item.port) else { return false }
        let blocked = ["ControlCenter", "rapportd", "postgres", "adb", "mysqld", "redis-server"]
        let noisy = blocked.contains { item.name == String($0.prefix(9)) }
        return !noisy
    }

    nonisolated static func parseProcs(_ out: String) -> [ProcRow] {
        var rows: [ProcRow] = []
        for line in out.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count == 5,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]),
                  let cpu = Double(parts[2].replacingOccurrences(of: ",", with: ".")),
                  let rss = Int64(parts[3]) else { continue }
            let comm = String(parts[4])
            if comm.isEmpty { continue }
            rows.append(ProcRow(pid: pid, ppid: ppid, cpu: cpu, rssKB: rss, comm: comm))
        }
        return rows
    }

    nonisolated static func readProcs() -> [ProcRow] {
        parseProcs(sh("ps -Aceo pid=,ppid=,pcpu=,rss=,comm=").out)
    }

    /// Helpers roll up into the nearest bundled app within 6 steps. The rest stay grouped by process name.
    static func groupHogs(_ rows: [ProcRow]) -> [Hog] {
        let byPid = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var appAt: [Int32: NSRunningApplication?] = [:]
        func bundled(_ pid: Int32) -> NSRunningApplication? {
            if let hit = appAt[pid] { return hit }
            let app = NSRunningApplication(processIdentifier: pid)
            let real = app?.bundleURL != nil ? app : nil
            appAt[pid] = real
            return real
        }
        func owner(_ pid: Int32) -> NSRunningApplication? {
            var current = pid
            for _ in 0..<6 {
                if let app = bundled(current) { return app }
                guard let row = byPid[current], row.ppid > 1, row.ppid != current else { return nil }
                current = row.ppid
            }
            return nil
        }
        var acc: [String: Hog] = [:]
        for row in rows {
            if let app = owner(row.pid) {
                let id = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
                var hog = acc[id] ?? Hog(id: id, name: app.localizedName ?? row.comm, cpu: 0, rssKB: 0,
                                          icon: app.icon, app: app, canQuit: canQuit(app))
                hog.cpu += row.cpu
                hog.rssKB += row.rssKB
                acc[id] = hog
            } else {
                let id = "proc:\(row.comm)"
                var hog = acc[id] ?? Hog(id: id, name: row.comm, cpu: 0, rssKB: 0, icon: nil, app: nil, canQuit: false)
                hog.cpu += row.cpu
                hog.rssKB += row.rssKB
                acc[id] = hog
            }
        }
        return Array(acc.values)
    }

    static func canQuit(_ app: NSRunningApplication) -> Bool {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return false }
        let bid = app.bundleIdentifier ?? ""
        if !bid.isEmpty && bid == Bundle.main.bundleIdentifier { return false }
        if ["com.apple.finder", "com.apple.dock", "com.apple.loginwindow"].contains(bid) { return false }
        let blocked: Set<String> = ["finder", "dock", "loginwindow", "mactools", "mactoolsbin"]
        let names = [app.localizedName, app.executableURL?.lastPathComponent].compactMap { $0?.lowercased() }
        return !names.contains(where: blocked.contains)
    }

    private static func checkParser() {
        let rows = parseProcs("  12   1  1.5  2048 Google Chrome Helper\n9 1 0,5 10 kernel_task\nbad\n")
        precondition(rows.count == 2 && rows[0].comm == "Google Chrome Helper" && rows[0].cpu == 1.5 && rows[0].rssKB == 2048)
        precondition(rows[1].pid == 9 && rows[1].cpu == 0.5 && rows[1].comm == "kernel_task")
        precondition(isDevPort(3000) && isDevPort(4200) && isDevPort(5173) && isDevPort(5174) && isDevPort(8081) && isDevPort(19006))
        precondition(!isDevPort(5000) && !isDevPort(5172) && !isDevPort(5175) && !isDevPort(443))
        precondition(!isDashboardDev(PortItem(name: "ControlCe", pid: 1, port: 3000)))
        precondition(!isDashboardDev(PortItem(name: "redis-ser", pid: 1, port: 8000)))
        precondition(!isDashboardDev(PortItem(name: "postgres", pid: 1, port: 3000)))
        precondition(isDashboardDev(PortItem(name: "node", pid: 1, port: 3000)))
        precondition(!isDashboardDev(PortItem(name: "node", pid: 1, port: 5000)))
    }

    // cpu_ticks order: user, system, idle, nice.
    nonisolated static func readTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return CPUTicks(user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
                        idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
    }

    nonisolated static func readRAM() -> Double? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        var page: vm_size_t = 0
        guard host_page_size(mach_host_self(), &page) == KERN_SUCCESS, page > 0 else { return nil }
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * UInt64(page)
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return nil }
        return min(1, Double(used) / Double(total))
    }

    nonisolated static func readDisk() -> (free: Int64, total: Int64) {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ])
        let free = v?.volumeAvailableCapacityForImportantUsage ?? 0
        let total = Int64(v?.volumeTotalCapacity ?? 0)
        return (max(free, 0), max(total, 1))
    }

    nonisolated static func probeNet() -> NetSnapshot {
        let summary = sh("ipconfig getsummary en0 2>/dev/null").out
        let ping = sh("ping -c1 -t2 1.1.1.1")
        return NetSnapshot(ssid: parseSSID(summary), online: ping.code == 0, ms: ping.code == 0 ? parsePing(ping.out) : nil)
    }

    nonisolated static func parseSSID(_ out: String) -> String {
        for line in out.split(separator: "\n") {
            let s = String(line)
            guard let r = s.range(of: " SSID : ") else { continue }
            let name = s[r.upperBound...].trimmingCharacters(in: .whitespaces)
            if name.isEmpty || name == "<redacted>" { return "—" }
            return name
        }
        return "—"
    }

    nonisolated static func parsePing(_ out: String) -> Int? {
        guard let r = out.range(of: "time=") else { return nil }
        let num = out[r.upperBound...].prefix { $0.isNumber || $0 == "." }
        return Double(num).map { Int($0.rounded()) }
    }

    /// `.git` is one level under the repo, so maxdepth 4 covers repos three levels under ~/projects.
    /// GIT_OPTIONAL_LOCKS=0 keeps `status` from taking the index lock.
    nonisolated static func scanGit() -> [RepoChange] {
        let root = home + "/projects"
        let cmd = """
        export GIT_OPTIONAL_LOCKS=0
        find \(q(root)) -maxdepth 4 -name .git -prune -print0 2>/dev/null | xargs -0 -n 1 -P 8 zsh -c '
        gitdir="$1"
        [ -n "$gitdir" ] || exit 0
        repo="${gitdir%/.git}"
        dirty=0
        [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ] && dirty=1
        ahead=$(git -C "$repo" rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
        case "$ahead" in ""|*[!0-9]*) ahead=0 ;; esac
        if [ "$dirty" = 1 ] || [ "$ahead" -gt 0 ]; then
          printf "%s\\t%s\\t%s\\n" "$repo" "$dirty" "$ahead"
        fi
        ' _
        """
        var list: [RepoChange] = []
        var seen = Set<String>()
        for line in sh(cmd).out.split(separator: "\n") {
            let p = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 3, seen.insert(p[0]).inserted else { continue }
            let ahead = Int(p[2]) ?? 0
            list.append(RepoChange(path: p[0], dirty: p[1] == "1", unpushed: ahead > 0))
        }
        return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

func gitPhrase(_ n: Int) -> String {
    switch n {
    case 0: "كله نضيف ✓"
    case 1: "مشروع واحد فيه تعديلات"
    case 2: "مشروعين فيهم تعديلات"
    default: "\(n) مشاريع فيها تعديلات"
    }
}

// MARK: - Bits of UI

struct DiskRing: View {
    var free: Int64
    var total: Int64
    private var used: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(total - free) / Double(total)))
    }
    private var tint: Color { used > 0.9 ? .red : used > 0.75 ? .orange : .green }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 7)
            Circle()
                .trim(from: 0, to: used)
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: used)
            VStack(spacing: 0) {
                Text(ByteCountFormatter.string(fromByteCount: max(free, 0), countStyle: .file))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("فاضي").font(.system(size: 8)).foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .frame(width: 72, height: 72)
    }
}

struct Sparkline: View {
    var values: [Double]
    var body: some View {
        GeometryReader { g in
            let vals = values.isEmpty ? [0] : values
            Path { p in
                let n = vals.count
                let peak = max(vals.max() ?? 1, 1)
                for i in 0..<n {
                    let x = n == 1 ? 0 : g.size.width * CGFloat(i) / CGFloat(n - 1)
                    let y = g.size.height * (1 - CGFloat(vals[i] / peak))
                    let pt = CGPoint(x: x, y: y)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    if n == 1 { p.addLine(to: CGPoint(x: g.size.width, y: y)) }
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct HogRow: View {
    let hog: Hog
    let kind: HogKind
    let top: Double
    var quit: () -> Void
    @State private var hover = false

    private var value: Double { kind == .cpu ? hog.cpu : Double(hog.rssKB) }
    private var label: String {
        if kind == .cpu { return String(format: "%.1f%%", hog.cpu) }
        return ByteCountFormatter.string(fromByteCount: hog.rssKB * 1024, countStyle: .memory)
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = hog.icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "gearshape").frame(width: 16).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(hog.name).font(.callout).lineLimit(1)
                    Spacer(minLength: 4)
                    if hover && hog.canQuit {
                        Button("اقفل", action: quit)
                            .buttonStyle(.borderless)
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    }
                    Text(label)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                GeometryReader { g in
                    let w = top > 0 ? g.size.width * CGFloat(min(1, value / top)) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(Color.accentColor).frame(width: w, alignment: .leading)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.snappy) { hover = inside }
        }
    }
}

private struct DashClipRow: View {
    let text: String
    @State private var copied = false
    @State private var hover = false

    private var technical: Bool {
        text.hasPrefix("http") || text.contains("://") || text.contains("{") || text.contains(";")
            || text.contains("func ") || text.contains("=>") || text.contains("</")
    }
    private var line: String {
        text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
    }

    var body: some View {
        Button {
            copyToClipboard(text)
            withAnimation { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                if copied { withAnimation { copied = false } }
            }
        } label: {
            HStack(spacing: 6) {
                Text(line)
                    .font(technical ? .system(.caption, design: .monospaced) : .callout)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, technical ? .leftToRight : .rightToLeft)
                if copied { Text("اتنسخ ✓").font(.caption).foregroundStyle(.green) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hover ? 0.08 : 0.03)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private func percentText(_ value: Double?) -> String {
    guard let value else { return "…" }
    return "\(Int(value.rounded()))%"
}

private func pill(_ text: String, _ color: Color) -> some View {
    Text(text).font(.caption2.bold())
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.18)))
        .foregroundStyle(color)
}

// MARK: - Dashboard

struct DashboardView: View {
    var open: (Tool) -> Void
    @ObservedObject private var model = DashboardModel.shared
    @ObservedObject private var clips = ClipboardStore.shared
    @ObservedObject private var reclaim = ReclaimStore.shared
    @ObservedObject private var stats = ActivityStats.shared
    @ObservedObject private var awake = KeepAwake.shared
    @State private var gitOpen = false
    @State private var hogKind = HogKind.cpu
    @State private var pendingQuit: Hog?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "wrench.and.screwdriver.fill").font(.title2).foregroundStyle(.tint)
                Text("MacTools").font(.title2.bold())
                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.borderless).help("خروج")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    clipboardCard
                    statsCard
                    hogsCard
                    if !model.devPorts.isEmpty { devCard.transition(.opacity.combined(with: .move(edge: .top))) }
                    reclaimCard
                    gitCard
                    activityCard
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .onAppear { model.setDashboard(true) }
        .onDisappear { model.setDashboard(false) }
        .alert("تقفل \(pendingQuit?.name ?? "")؟", isPresented: Binding(
            get: { pendingQuit != nil },
            set: { if !$0 { pendingQuit = nil } }
        )) {
            Button("اقفل", role: .destructive) {
                if pendingQuit?.canQuit == true { pendingQuit?.app?.terminate() }
                pendingQuit = nil
            }
            Button("إلغاء", role: .cancel) { pendingQuit = nil }
        } message: {
            Text("هيخرج لوحده.")
        }
    }

    private var clipboardCard: some View {
        Card {
            Text("آخر حاجات نسختها").font(.subheadline.bold())
            if clips.items.isEmpty {
                Text("لسه مفيش حاجة اتنسخت").foregroundStyle(.secondary)
            } else {
                ForEach(Array(clips.items.prefix(5)), id: \.self) { s in
                    DashClipRow(text: s)
                }
            }
        }
    }

    private var statsCard: some View {
        Card {
            HStack(alignment: .center, spacing: 10) {
                DiskRing(free: model.diskFree, total: model.diskTotal)
                VStack(alignment: .leading, spacing: 3) {
                    meter("المعالج", model.cpu)
                    meter("الرام", model.ram.map { $0 * 100 })
                    Sparkline(values: model.cpuHist).frame(height: 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Label(model.net.ssid, systemImage: "wifi")
                        .font(.caption.bold())
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(model.net.online ? Color.green : Color.secondary).frame(width: 6, height: 6)
                        Text(model.net.online ? "متصل" : "أوفلاين")
                            .font(.caption2.bold())
                            .foregroundStyle(model.net.online ? Color.green : Color.secondary)
                    }
                    Text(model.net.ms.map { "\($0) ms" } ?? "—")
                        .font(.caption.monospacedDigit())
                        .contentTransition(.numericText())
                }
                .frame(width: 108, alignment: .leading)
            }
        }
    }

    private func meter(_ title: String, _ value: Double?) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(percentText(value))
                .font(.caption.bold().monospacedDigit())
                .contentTransition(.numericText())
        }
    }

    private var topHogs: [Hog] {
        let sorted = model.hogs.sorted { a, b in
            let byUse: Bool = hogKind == .cpu ? a.cpu > b.cpu : a.rssKB > b.rssKB
            if hogKind == .cpu ? a.cpu != b.cpu : a.rssKB != b.rssKB { return byUse }
            return a.name < b.name
        }
        return Array(sorted.prefix(5))
    }

    private var hogsCard: some View {
        let rows = topHogs
        let top = rows.map { hogKind == .cpu ? $0.cpu : Double($0.rssKB) }.max() ?? 0
        return Card {
            HStack(spacing: 8) {
                Text("أكتر حاجة بتستهلك").font(.subheadline.bold()).lineLimit(1)
                Spacer(minLength: 4)
                Picker("", selection: Binding(
                    get: { hogKind },
                    set: { kind in withAnimation(.snappy) { hogKind = kind } }
                )) {
                    Text("المعالج").tag(HogKind.cpu)
                    Text("الرام").tag(HogKind.ram)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 148)
            }
            if rows.isEmpty {
                Text(model.hogsReady ? "مفيش استهلاك ظاهر" : "بحسب الاستهلاك…")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(rows) { hog in
                    HogRow(hog: hog, kind: hogKind, top: top) { pendingQuit = hog }
                }
            }
        }
    }

    private var devCard: some View {
        let shown = Array(model.devPorts.prefix(4))
        let extra = model.devPorts.count - shown.count
        return Card {
            Text("سيرفرات شغالة").font(.subheadline.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(shown) { item in
                    HStack(spacing: 4) {
                        if let tag = item.tag, tag == "Metro" || tag == "Expo" || tag == "Vite" {
                            Text(tag).font(.caption2.bold())
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange.opacity(0.2)))
                        }
                        Text(item.name).lineLimit(1)
                        Text(":\(item.port)").font(.system(.caption, design: .monospaced))
                        Button { Task { await model.kill(item) } } label: {
                            Image(systemName: "xmark").font(.caption2.bold())
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .help("اقفل")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                if extra > 0 {
                    Button { open(.ports) } label: {
                        Text("+\(extra)").font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var reclaimCard: some View {
        Button { open(.clean) } label: {
            Card {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("ممكن توفر")
                            Text(reclaim.at == nil ? "…" : human(kb: reclaim.kb))
                                .contentTransition(.numericText())
                        }
                        .font(.headline)
                        if let at = reclaim.at {
                            TimelineView(.periodic(from: .now, by: 30)) { _ in
                                Text(reclaimAgo(at)).font(.caption2).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("بحسب المساحة…").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.left").font(.caption).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var gitCard: some View {
        Card {
            if let repos = model.git {
                Button {
                    if !repos.isEmpty { withAnimation(.snappy) { gitOpen.toggle() } }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary)
                        Text(gitPhrase(repos.count))
                            .font(.subheadline.bold())
                            .contentTransition(.numericText())
                        Spacer(minLength: 4)
                        if !repos.isEmpty {
                            Image(systemName: gitOpen ? "chevron.up" : "chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                if gitOpen {
                    ForEach(repos) { repo in
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: repo.path))
                        } label: {
                            HStack(spacing: 6) {
                                Text(repo.name).lineLimit(1)
                                Spacer(minLength: 4)
                                if repo.dirty { pill("تعديلات", .orange) }
                                if repo.unpushed { pill("مش مرفوع", .blue) }
                            }
                            .font(.callout)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Busy(text: "بدوّر على المشاريع…")
            }
        }
    }

    private var activityCard: some View {
        Card {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(.mint)
                Text("وفرت")
                Text(ByteCountFormatter.string(fromByteCount: stats.bytesFreed, countStyle: .file))
                    .contentTransition(.numericText())
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle").foregroundStyle(.red)
                Text("حمّلت")
                Text("\(stats.downloadsThisWeek)").contentTransition(.numericText()).monospacedDigit()
                Text("الأسبوع ده")
            }
            if awake.isOn {
                Text("☕ منع النوم شغال").foregroundStyle(.orange)
            }
        }
    }
}
