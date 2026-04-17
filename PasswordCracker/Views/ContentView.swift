import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: JobStore
    @State private var showNewJob = false

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            JobListView(showNewJob: $showNewJob)
        } detail: {
            if let job = store.selectedJob {
                JobDetailView(job: job)
            } else {
                EmptyStateView(
                    icon: "lock.shield",
                    title: "Password Cracker",
                    message: "Create a new job to start cracking"
                )
            }
        }
        .sheet(isPresented: $showNewJob) {
            NewJobView()
        }
        #else
        NavigationStack {
            JobListView(showNewJob: $showNewJob)
                .sheet(isPresented: $showNewJob) {
                    NewJobView()
                }
        }
        #endif
    }
}
