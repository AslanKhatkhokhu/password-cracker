import SwiftUI

struct JobDetailView: View {
    @EnvironmentObject private var store: JobStore
    @ObservedObject var job: CrackJob
    @State private var timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                statsGrid
                candidateCard
                resultCard
                controlButtons
            }
            .padding()
        }
        .navigationTitle(job.name)
        .onReceive(timer) { _ in
            // Force refresh for elapsed time
            job.objectWillChange.send()
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 16) {
            Image(systemName: job.targetType.icon)
                .font(.system(size: 32))
                .foregroundStyle(headerColor)
                .frame(width: 52, height: 52)
                .background(headerColor.opacity(0.1))
                .cornerRadius(Theme.cornerRadius)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(Theme.title)
                HStack(spacing: 8) {
                    Label(job.targetType.rawValue, systemImage: job.targetType.icon)
                    Text("·")
                    Label(job.attackMode.rawValue, systemImage: job.attackMode.icon)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            statusPill
        }
        .cardStyle()
    }

    private var statusPill: some View {
        Text(job.status.label)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(headerColor.opacity(0.12))
            .foregroundStyle(headerColor)
            .cornerRadius(20)
    }

    private var headerColor: Color {
        switch job.status {
        case .idle:              return .secondary
        case .running:           return .blue
        case .paused:            return .orange
        case .completed(true):   return .green
        case .completed(false):  return .red
        case .error:             return .orange
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: Theme.spacing) {
            StatCard(
                icon: "number",
                value: formatCount(job.attemptCount),
                title: "Attempts",
                color: .blue
            )
            StatCard(
                icon: "gauge.with.needle",
                value: formatSpeed(job.speed),
                title: "Speed",
                color: .purple
            )
            StatCard(
                icon: "clock",
                value: formatElapsed(job.elapsed),
                title: "Elapsed",
                color: .orange
            )
        }
    }

    // MARK: - Current Candidate

    private var candidateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENT CANDIDATE")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .tracking(0.5)

            Text(job.currentCandidate.isEmpty ? "—" : job.currentCandidate)
                .font(Theme.mono)
                .foregroundStyle(job.currentCandidate.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            if case .running = job.status {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }
        }
        .cardStyle()
    }

    // MARK: - Result Card

    @ViewBuilder
    private var resultCard: some View {
        if case .completed(let found) = job.status {
            VStack(spacing: 12) {
                Image(systemName: found ? "lock.open.fill" : "lock.slash.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(found ? .green : .red)

                if found, let password = job.foundPassword {
                    Text("PASSWORD FOUND")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                        .tracking(1)

                    Text(password)
                        .font(Theme.monoLarge)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal)

                    Button {
                        copyToClipboard(password)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Text("PASSWORD NOT FOUND")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                        .tracking(1)

                    Text("All candidates exhausted")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .cardStyle()
        }

        if case .error(let msg) = job.status {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .cardStyle()
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlButtons: some View {
        HStack(spacing: 12) {
            switch job.status {
            case .idle:
                Button {
                    store.engine.start(job: job)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .running:
                Button {
                    store.engine.pause(job: job)
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(role: .destructive) {
                    store.engine.stop(job: job)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

            case .paused:
                Button {
                    store.engine.resume(job: job)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .destructive) {
                    store.engine.stop(job: job)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

            case .completed, .error:
                EmptyView()
            }
        }
    }

    // MARK: - Formatting

    private func formatCount(_ count: Int64) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func formatSpeed(_ speed: Double) -> String {
        if speed >= 1_000_000 { return String(format: "%.1fM/s", speed / 1_000_000) }
        if speed >= 1_000 { return String(format: "%.1fK/s", speed / 1_000) }
        return String(format: "%.0f/s", speed)
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
