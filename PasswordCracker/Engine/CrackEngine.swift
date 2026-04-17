import Foundation

// MARK: - Crack Engine

/// Orchestrates password cracking: connects PasswordGenerator → target cracker → progress updates.
/// Runs on a background task, updates the CrackJob on the main actor.
@MainActor
final class CrackEngine: ObservableObject {
    private var task: Task<Void, Never>?
    private var isPaused = false
    private var pauseContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Start

    func start(job: CrackJob) {
        guard case .idle = job.status else { return }

        job.status = .running
        job.startTime = Date()
        job.attemptCount = 0
        job.foundPassword = nil

        task = Task { [weak self] in
            await self?.run(job: job)
        }
    }

    // MARK: - Pause / Resume / Stop

    func pause(job: CrackJob) {
        isPaused = true
        job.status = .paused
    }

    func resume(job: CrackJob) {
        isPaused = false
        job.status = .running
        pauseContinuation?.resume()
        pauseContinuation = nil
    }

    func stop(job: CrackJob) {
        task?.cancel()
        task = nil
        isPaused = false
        pauseContinuation?.resume()
        pauseContinuation = nil
        job.endTime = Date()
        if job.foundPassword == nil {
            job.status = .completed(found: false)
        }
    }

    // MARK: - Core Loop

    private func run(job: CrackJob) async {
        // Validate target
        let validationResult = await validateTarget(job: job)
        if case .failure(let err) = validationResult {
            job.status = .error(err.localizedDescription)
            job.endTime = Date()
            return
        }

        // Get password stream
        let passwords = passwordStream(for: job)

        var lastSpeedUpdate = Date()
        var countSinceLastUpdate: Int64 = 0

        for await candidate in passwords {
            // Check cancellation
            if Task.isCancelled {
                job.endTime = Date()
                if job.foundPassword == nil {
                    job.status = .completed(found: false)
                }
                return
            }

            // Handle pause
            if isPaused {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.pauseContinuation = continuation
                }
                if Task.isCancelled { return }
            }

            // Try the password
            let success = await tryCandidate(candidate, job: job)

            job.attemptCount += 1
            countSinceLastUpdate += 1

            // Update UI periodically (every 100ms worth of work or every 50 attempts)
            let now = Date()
            if countSinceLastUpdate >= 50 || now.timeIntervalSince(lastSpeedUpdate) >= 0.1 {
                job.currentCandidate = candidate
                let elapsed = now.timeIntervalSince(lastSpeedUpdate)
                if elapsed > 0 {
                    job.speed = Double(countSinceLastUpdate) / elapsed
                }
                lastSpeedUpdate = now
                countSinceLastUpdate = 0
            }

            if success {
                job.foundPassword = candidate
                job.currentCandidate = candidate
                job.endTime = Date()
                job.status = .completed(found: true)
                return
            }

            // Rate limiting for HTTP
            if job.targetType == .http && job.config.requestDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(job.config.requestDelay * 1_000_000_000))
            }
        }

        // Exhausted all candidates
        job.endTime = Date()
        job.status = .completed(found: false)
    }

    // MARK: - Target Validation

    private func validateTarget(job: CrackJob) async -> Result<Void, CrackerError> {
        switch job.targetType {
        case .pdf:
            guard let url = job.fileURL else { return .failure(.fileNotFound) }
            return PDFCracker.validate(url: url)
        case .doc:
            guard let url = job.fileURL else { return .failure(.fileNotFound) }
            return DOCCracker.validate(url: url)
        case .http:
            return await HTTPCracker.validate(config: job.config)
        }
    }

    // MARK: - Password Stream

    private func passwordStream(for job: CrackJob) -> AsyncStream<String> {
        switch job.attackMode {
        case .bruteForce:
            return PasswordGenerator.bruteForce(
                charset: job.config.charset,
                minLength: job.config.minLength,
                maxLength: job.config.maxLength
            )
        case .wordlist:
            guard let url = job.config.wordlistURL else {
                return AsyncStream { $0.finish() }
            }
            return PasswordGenerator.wordlist(url: url)
        case .keywordGen:
            return PasswordGenerator.keywordGen(keywords: job.config.keywords)
        }
    }

    // MARK: - Try Candidate

    private func tryCandidate(_ candidate: String, job: CrackJob) async -> Bool {
        let targetType = job.targetType
        let fileURL = job.fileURL
        let config = job.config

        switch targetType {
        case .pdf:
            guard let url = fileURL else { return false }
            return PDFCracker.tryPassword(candidate, fileURL: url)
        case .doc:
            guard let url = fileURL else { return false }
            return DOCCracker.tryPassword(candidate, fileURL: url)
        case .http:
            return await HTTPCracker.tryPassword(candidate, config: config)
        }
    }
}
