import Foundation
import CoreGraphics

// MARK: - PDF Cracker

/// Uses CGPDFDocument to test passwords against an encrypted PDF.
/// Works natively on macOS and iOS — no external dependencies.
enum PDFCracker {

    /// Returns `true` if the PDF at `url` is encrypted (locked).
    static func isEncrypted(url: URL) -> Bool {
        guard let doc = CGPDFDocument(url as CFURL) else { return false }
        // If the doc is unlocked already, it's not encrypted (or has empty password)
        return !doc.isUnlocked
    }

    /// Tries to unlock the PDF with the given password.
    /// Returns `true` if the password is correct.
    static func tryPassword(_ password: String, fileURL: URL) -> Bool {
        guard let doc = CGPDFDocument(fileURL as CFURL) else { return false }

        // Some PDFs are "encrypted" but unlock with an empty password
        if doc.isUnlocked { return false }

        return doc.unlockWithPassword(password)
    }

    /// Validates that the file at `url` is a real PDF and is encrypted.
    static func validate(url: URL) -> Result<Void, CrackerError> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.fileNotFound)
        }
        guard let doc = CGPDFDocument(url as CFURL) else {
            return .failure(.invalidFile("Not a valid PDF"))
        }
        if doc.isUnlocked {
            // Try empty password — some PDFs have owner-only protection
            if doc.unlockWithPassword("") {
                return .failure(.notEncrypted)
            }
            return .failure(.notEncrypted)
        }
        return .success(())
    }
}
