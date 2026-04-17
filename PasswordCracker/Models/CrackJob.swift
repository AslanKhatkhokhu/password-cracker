import Foundation

// MARK: - Target Type

enum TargetType: String, CaseIterable, Identifiable {
    case pdf = "PDF"
    case doc = "DOC / DOCX"
    case http = "HTTP"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pdf:  return "doc.richtext"
        case .doc:  return "doc.text"
        case .http: return "globe"
        }
    }
}

// MARK: - Attack Mode

enum AttackMode: String, CaseIterable, Identifiable {
    case bruteForce = "Brute Force"
    case wordlist = "Wordlist"
    case keywordGen = "Keyword Generator"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bruteForce:  return "lock.open.rotation"
        case .wordlist:    return "list.bullet.rectangle"
        case .keywordGen:  return "text.word.spacing"
        }
    }

    var description: String {
        switch self {
        case .bruteForce:  return "Try every combination of a character set"
        case .wordlist:    return "Test passwords from a wordlist file"
        case .keywordGen:  return "Generate mutations from keywords"
        }
    }
}

// MARK: - Charset

enum CharsetOption: String, CaseIterable, Identifiable {
    case digits = "0–9"
    case lowercase = "a–z"
    case uppercase = "A–Z"
    case alpha = "a–zA–Z"
    case alphanumeric = "a–zA–Z0–9"
    case allPrintable = "All Printable"

    var id: String { rawValue }

    var characters: String {
        switch self {
        case .digits:       return "0123456789"
        case .lowercase:    return "abcdefghijklmnopqrstuvwxyz"
        case .uppercase:    return "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        case .alpha:        return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        case .alphanumeric: return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        case .allPrintable: return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{}|;:',.<>?/`~\"\\ "
        }
    }
}

// MARK: - HTTP Method

enum HTTPAttackMethod: String, CaseIterable, Identifiable {
    case basicAuth = "Basic Auth"
    case postForm = "POST Form"
    case getParam = "GET Parameter"

    var id: String { rawValue }
}

// MARK: - Job Status

enum JobStatus: Equatable {
    case idle
    case running
    case paused
    case completed(found: Bool)
    case error(String)

    var label: String {
        switch self {
        case .idle:                return "Ready"
        case .running:             return "Running"
        case .paused:              return "Paused"
        case .completed(let ok):   return ok ? "Cracked" : "Exhausted"
        case .error(let msg):      return "Error: \(msg)"
        }
    }
}

// MARK: - Attack Configuration

struct AttackConfig {
    // Brute force
    var charset: CharsetOption = .lowercase
    var minLength: Int = 1
    var maxLength: Int = 6

    // Wordlist
    var wordlistURL: URL?

    // Keyword gen
    var keywords: [String] = []

    // HTTP
    var httpURL: String = ""
    var httpMethod: HTTPAttackMethod = .basicAuth
    var username: String = "admin"
    var usernameField: String = "username"
    var passwordField: String = "password"
    var successIndicator: String = ""
    var requestDelay: Double = 0 // seconds between requests
}

// MARK: - Crack Job

@MainActor
final class CrackJob: ObservableObject, Identifiable {
    let id = UUID()
    let createdAt = Date()

    // Config
    var name: String
    var targetType: TargetType
    var attackMode: AttackMode
    var config: AttackConfig
    var fileURL: URL?

    // Progress
    @Published var status: JobStatus = .idle
    @Published var currentCandidate: String = ""
    @Published var attemptCount: Int64 = 0
    @Published var speed: Double = 0
    @Published var startTime: Date?
    @Published var endTime: Date?

    // Result
    @Published var foundPassword: String?

    var elapsed: TimeInterval {
        guard let start = startTime else { return 0 }
        let end = endTime ?? Date()
        return end.timeIntervalSince(start)
    }

    init(name: String, targetType: TargetType, attackMode: AttackMode, config: AttackConfig, fileURL: URL? = nil) {
        self.name = name
        self.targetType = targetType
        self.attackMode = attackMode
        self.config = config
        self.fileURL = fileURL
    }
}
