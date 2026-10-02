import SwiftUI

// Shared usage-card palette.
private let claudeBarBase = Color(hex: "#5B8DEF")
private let glmBarBase = Color(hex: "#E0A030")

/// nil → grey track, ≥ 90 → red, ≥ 75 → amber, else the provider base colour.
private func barColor(pct: Int?, base: Color) -> Color {
    guard let p = pct else { return Color(hex: "#3B4559") }
    if p >= 90 { return Color(hex: "#F26B5B") }
    if p >= 75 { return Color(hex: "#F5A524") }
    return base
}

private func pctText(_ p: Int?) -> String {
    p.map { "\($0)%" } ?? "—"
}

/// nil → "", same calendar day → "HH:mm", otherwise → "EEE" (e.g. "Mon").
private func resetText(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let f = DateFormatter()
    f.locale = Locale.current
    if Calendar.current.isDate(d, inSameDayAs: Date()) {
        f.dateFormat = "HH:mm"
    } else {
        f.dateFormat = "EEE"
    }
    return f.string(from: d)
}

private func timeHHmm(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let f = DateFormatter()
    f.locale = Locale.current
    f.dateFormat = "HH:mm"
    return f.string(from: d)
}

private func fullWhen(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale.current
    f.dateFormat = "EEE HH:mm"
    return f.string(from: d)
}

private func joinResets(_ a: Date?, _ b: Date?) -> String {
    [resetText(a), resetText(b)].filter { !$0.isEmpty }.joined(separator: " · ")
}

/// One labelled progress bar row: 48-pt label, flexible track, 36-pt monospaced value.
private struct UsageRow: View {
    let label: String
    let pct: Int?
    let base: Color
    let dim: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(Color(hex: "#9AA3B2"))
                .frame(width: 40, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: "#1E2330"))
                    Capsule().fill(barColor(pct: pct, base: base))
                        .frame(width: max(0, min(100, Double(pct ?? 0))) / 100 * geo.size.width)
                }
            }
            .frame(height: 6)
            Text(pctText(pct))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(Color(hex: "#C9D0DB"))
                .frame(width: 30, alignment: .trailing)
        }
        .opacity(dim ? 0.45 : 1)
    }
}

/// 4-pt mini bar for the one-line strip.
private struct MiniBar: View {
    let pct: Int?
    let base: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: "#1E2330"))
                Capsule().fill(barColor(pct: pct, base: base))
                    .frame(width: max(0, min(100, Double(pct ?? 0))) / 100 * geo.size.width)
            }
        }
        .frame(width: 44, height: 4)
    }
}

/// Full card: two groups, two bars each. Used when no agent pills share the panel.
struct UsageCardView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) { claudeSection }
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Color(hex: "#1E2330")).frame(width: 1)
            VStack(alignment: .leading, spacing: 6) { glmSection }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }

    private var titleFont: Font { .system(size: 9.5).monospaced() }
    private var titleColor: Color { Color(hex: "#7F8A9B") }

    @ViewBuilder
    private var claudeSection: some View {
        let c = state.claudeUsage
        if c.updatedAt == nil {
            Text("claude").font(titleFont).foregroundColor(titleColor)
            Text(HookServer.statusLineRelayInstalled() ? "not reporting yet" : "install the relay in Settings")
                .font(titleFont).foregroundColor(titleColor).lineLimit(2)
        } else {
            Text(c.isStale ? "claude · as of \(timeHHmm(c.updatedAt))" : "claude")
                .font(titleFont).foregroundColor(titleColor).lineLimit(1)
            UsageRow(label: "5 hour", pct: c.fiveHourPct, base: claudeBarBase, dim: c.isStale)
            UsageRow(label: "7 day", pct: c.sevenDayPct, base: claudeBarBase, dim: c.isStale)
            Text("resets \(joinResets(c.fiveHourResetsAt, c.sevenDayResetsAt))")
                .font(titleFont).foregroundColor(titleColor).lineLimit(1)
        }
    }

    @ViewBuilder
    private var glmSection: some View {
        let g = state.zaiUsage
        if let e = g.error {
            Text("glm").font(titleFont).foregroundColor(titleColor)
            Text(e).font(titleFont).foregroundColor(Color(hex: "#F26B5B")).lineLimit(2)
        } else if (KeychainStore.shared.get("zai-api-key") ?? "").isEmpty {
            Text("glm").font(titleFont).foregroundColor(titleColor)
            Text("add the Z.ai key in Settings").font(titleFont).foregroundColor(titleColor).lineLimit(2)
        } else {
            Text("glm · z.ai \(g.level ?? "")" + (g.isStale ? " · as of \(timeHHmm(g.updatedAt))" : ""))
                .font(titleFont).foregroundColor(titleColor).lineLimit(1)
            UsageRow(label: "5 hour", pct: g.fiveHourPct, base: glmBarBase, dim: g.isStale)
            UsageRow(label: "weekly", pct: g.weeklyPct, base: glmBarBase, dim: g.isStale)
            Text("resets \(joinResets(g.fiveHourResetsAt, g.weeklyResetsAt))")
                .font(titleFont).foregroundColor(titleColor).lineLimit(1)
        }
    }
}

/// One-line strip: "C ▮▮▮ 61 · 23   G ▮ 3 · 18". Used under the pills when workers run.
struct UsageStripView: View {
    @ObservedObject var state: AppState

    var body: some View {
        let c = state.claudeUsage
        let g = state.zaiUsage
        let cKnown = c.fiveHourPct != nil || c.sevenDayPct != nil
        let cMax = max(c.fiveHourPct ?? 0, c.sevenDayPct ?? 0)
        let gKnown = g.fiveHourPct != nil || g.weeklyPct != nil
        let gMax = max(g.fiveHourPct ?? 0, g.weeklyPct ?? 0)
        return HStack(spacing: 6) {
            Text("C")
                .font(.system(size: 9.5).monospaced())
                .foregroundColor(claudeBarBase)
            MiniBar(pct: cKnown ? cMax : nil, base: claudeBarBase)
            Text("\(c.fiveHourPct.map(String.init) ?? "—") · \(c.sevenDayPct.map(String.init) ?? "—")")
                .font(.system(size: 9.5).monospaced())
                .foregroundColor(cKnown && cMax >= 90 ? Color(hex: "#F26B5B") : Color(hex: "#C9D0DB"))
            Spacer().frame(width: 6)
            Text("G")
                .font(.system(size: 9.5).monospaced())
                .foregroundColor(glmBarBase)
            MiniBar(pct: gKnown ? gMax : nil, base: glmBarBase)
            Text("\(g.fiveHourPct.map(String.init) ?? "—") · \(g.weeklyPct.map(String.init) ?? "—")")
                .font(.system(size: 9.5).monospaced())
                .foregroundColor(gKnown && gMax >= 90 ? Color(hex: "#F26B5B") : Color(hex: "#C9D0DB"))
        }
        .frame(height: 16)
        .help(helpText)
    }

    private var helpText: String {
        let c = state.claudeUsage
        let g = state.zaiUsage
        var cl = "Claude: 5h \(pctText(c.fiveHourPct))"
        if let d = c.fiveHourResetsAt { cl += " (resets \(fullWhen(d)))" }
        cl += " · 7d \(pctText(c.sevenDayPct))"
        if let d = c.sevenDayResetsAt { cl += " (resets \(fullWhen(d)))" }
        var gl = "GLM: 5h \(pctText(g.fiveHourPct))"
        if let d = g.fiveHourResetsAt { gl += " (resets \(fullWhen(d)))" }
        gl += " · weekly \(pctText(g.weeklyPct))"
        if let d = g.weeklyResetsAt { gl += " (resets \(fullWhen(d)))" }
        return cl + "\n" + gl
    }
}
