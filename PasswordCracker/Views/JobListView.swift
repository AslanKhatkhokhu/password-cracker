import SwiftUI

struct JobListView: View {
    @EnvironmentObject private var store: JobStore
    @Binding var showNewJob: Bool

    var body: some View {
        List(selection: $store.selectedJobID) {
            if store.jobs.isEmpty {
                EmptyStateView(
                    icon: "plus.circle.dashed",
                    title: "No Jobs",
                    message: "Tap + to create a crack job"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(store.jobs) { job in
                    #if os(macOS)
                    JobRow(job: job)
                        .tag(job.id)
                    #else
                    NavigationLink(value: job.id) {
                        JobRow(job: job)
                    }
                    #endif
                }
                .onDelete(perform: deleteJobs)
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #else
        .listStyle(.insetGrouped)
        .navigationDestination(for: UUID.self) { id in
            if let job = store.jobs.first(where: { $0.id == id }) {
                JobDetailView(job: job)
            }
        }
        #endif
        .navigationTitle("Jobs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewJob = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private func deleteJobs(at offsets: IndexSet) {
        for index in offsets {
            store.removeJob(store.jobs[index])
        }
    }
}

// MARK: - Job Row

struct JobRow: View {
    @ObservedObject var job: CrackJob

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.targetType.icon)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(job.targetType.rawValue)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.12))
                        .foregroundStyle(statusColor)
                        .cornerRadius(4)
                    Text(job.attackMode.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusBadge
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch job.status {
        case .idle:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
        case .completed(let found):
            Image(systemName: found ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(found ? .green : .red)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .idle:                return .secondary
        case .running:             return .blue
        case .paused:              return .orange
        case .completed(let ok):   return ok ? .green : .red
        case .error:               return .orange
        }
    }
}
