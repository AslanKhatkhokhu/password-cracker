import SwiftUI

@main
struct PasswordCrackerApp: App {
    @StateObject private var store = JobStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 640)
        #endif
    }
}

// MARK: - Job Store

@MainActor
final class JobStore: ObservableObject {
    @Published var jobs: [CrackJob] = []
    @Published var selectedJobID: UUID?

    let engine = CrackEngine()

    var selectedJob: CrackJob? {
        jobs.first { $0.id == selectedJobID }
    }

    func addJob(_ job: CrackJob) {
        jobs.insert(job, at: 0)
        selectedJobID = job.id
    }

    func removeJob(_ job: CrackJob) {
        engine.stop(job: job)
        jobs.removeAll { $0.id == job.id }
        if selectedJobID == job.id {
            selectedJobID = jobs.first?.id
        }
    }
}
