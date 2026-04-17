import Foundation

enum CrackerError: LocalizedError {
    case fileNotFound
    case notEncrypted
    case invalidFile(String)
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:        return "File not found"
        case .notEncrypted:        return "File is not password-protected"
        case .invalidFile(let m):  return m
        case .cancelled:           return "Cancelled"
        case .unknown(let m):      return m
        }
    }
}
