import SwiftUI
import UniformTypeIdentifiers

struct NewJobView: View {
    @EnvironmentObject private var store: JobStore
    @Environment(\.dismiss) private var dismiss

    // Config
    @State private var name = ""
    @State private var targetType: TargetType = .pdf
    @State private var attackMode: AttackMode = .bruteForce
    @State private var config = AttackConfig()

    // File picker
    @State private var fileURL: URL?
    @State private var showFilePicker = false

    // Keyword input
    @State private var keywordInput = ""

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Job Name
                Section("Job Name") {
                    TextField("e.g. Client report PDF", text: $name)
                }

                // MARK: - Target Type
                Section("Target") {
                    Picker("Type", selection: $targetType) {
                        ForEach(TargetType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if targetType == .pdf || targetType == .doc {
                        filePickerButton
                    } else {
                        httpConfigSection
                    }
                }

                // MARK: - Attack Mode
                Section("Attack Mode") {
                    Picker("Mode", selection: $attackMode) {
                        ForEach(AttackMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    }

                    Text(attackMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    attackConfigSection
                }

                // MARK: - Start
                Section {
                    Button {
                        startJob()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Start Cracking", systemImage: "bolt.fill")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(!isValid)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Job")
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 520)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: allowedFileTypes,
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    if url.startAccessingSecurityScopedResource() {
                        fileURL = url
                    }
                }
            }
        }
    }

    // MARK: - File Picker

    @ViewBuilder
    private var filePickerButton: some View {
        Button {
            showFilePicker = true
        } label: {
            HStack {
                Image(systemName: "doc.badge.plus")
                if let url = fileURL {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                } else {
                    Text("Select File")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private var allowedFileTypes: [UTType] {
        switch targetType {
        case .pdf: return [.pdf]
        case .doc: return [
            .init(filenameExtension: "doc") ?? .data,
            .init(filenameExtension: "docx") ?? .data,
            .init(filenameExtension: "xlsx") ?? .data,
            .init(filenameExtension: "pptx") ?? .data,
        ]
        case .http: return []
        }
    }

    // MARK: - HTTP Config

    @ViewBuilder
    private var httpConfigSection: some View {
        TextField("URL", text: $config.httpURL)
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            #endif

        Picker("Method", selection: $config.httpMethod) {
            ForEach(HTTPAttackMethod.allCases) { method in
                Text(method.rawValue).tag(method)
            }
        }

        TextField("Username", text: $config.username)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif

        if config.httpMethod != .basicAuth {
            TextField("Username Field", text: $config.usernameField)
            TextField("Password Field", text: $config.passwordField)
        }

        TextField("Success Indicator (optional)", text: $config.successIndicator)
            .font(.caption)

        HStack {
            Text("Request Delay")
            Spacer()
            Text("\(config.requestDelay, specifier: "%.1f")s")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        Slider(value: $config.requestDelay, in: 0...5, step: 0.1)
    }

    // MARK: - Attack Config

    @ViewBuilder
    private var attackConfigSection: some View {
        switch attackMode {
        case .bruteForce:
            Picker("Charset", selection: $config.charset) {
                ForEach(CharsetOption.allCases) { cs in
                    Text(cs.rawValue).tag(cs)
                }
            }
            Stepper("Min Length: \(config.minLength)", value: $config.minLength, in: 1...12)
            Stepper("Max Length: \(config.maxLength)", value: $config.maxLength, in: 1...12)

        case .wordlist:
            Button {
                openWordlistPicker()
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                    if let url = config.wordlistURL {
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                    } else {
                        Text("Select Wordlist (.txt)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

        case .keywordGen:
            TextField("Enter keywords (comma-separated)", text: $keywordInput)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            if !parsedKeywords.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(parsedKeywords, id: \.self) { kw in
                        Text(kw)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .cornerRadius(6)
                    }
                }

                Text("~\(estimatedMutations) password candidates will be generated")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Wordlist Picker

    @State private var showWordlistPickerSheet = false

    private func openWordlistPicker() {
        self.showWordlistPickerSheet = true
    }

    // MARK: - Helpers

    private var parsedKeywords: [String] {
        keywordInput
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var estimatedMutations: Int {
        let count = parsedKeywords.count
        guard count > 0 else { return 0 }
        // Each keyword generates ~80 mutations, pairs add ~10 * count*(count-1) more
        return count * 80 + count * (count - 1) * 15
    }

    private var isValid: Bool {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        switch targetType {
        case .pdf, .doc:
            return fileURL != nil
        case .http:
            return !config.httpURL.isEmpty
        }
    }

    // MARK: - Start Job

    private func startJob() {
        if attackMode == .keywordGen {
            config.keywords = parsedKeywords
        }

        let job = CrackJob(
            name: name.trimmingCharacters(in: .whitespaces),
            targetType: targetType,
            attackMode: attackMode,
            config: config,
            fileURL: fileURL
        )

        store.addJob(job)
        store.engine.start(job: job)
        dismiss()
    }
}

// MARK: - Flow Layout (keyword tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                   proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
