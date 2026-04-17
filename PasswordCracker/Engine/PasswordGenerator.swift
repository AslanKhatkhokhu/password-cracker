import Foundation

// MARK: - Password Generator

/// Produces password candidates for all three attack modes.
/// Designed as an AsyncSequence so the engine can iterate lazily.
enum PasswordGenerator {

    // MARK: - Brute Force

    /// Yields every combination of `charset` from length `minLen` to `maxLen`.
    static func bruteForce(charset: CharsetOption, minLength: Int, maxLength: Int) -> AsyncStream<String> {
        let chars = Array(charset.characters)
        let min = max(minLength, 1)
        let maxLen = max(maxLength, min)

        return AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                for length in min...maxLen {
                    var indices = Array(repeating: 0, count: length)
                    while true {
                        if Task.isCancelled { continuation.finish(); return }

                        let candidate = String(indices.map { chars[$0] })
                        continuation.yield(candidate)

                        // Increment odometer-style
                        var pos = length - 1
                        while pos >= 0 {
                            indices[pos] += 1
                            if indices[pos] < chars.count { break }
                            indices[pos] = 0
                            pos -= 1
                        }
                        if pos < 0 { break } // all combos for this length done
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Wordlist

    /// Reads lines from a wordlist file and yields each as a candidate.
    static func wordlist(url: URL) -> AsyncStream<String> {
        return AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                guard let data = try? Data(contentsOf: url),
                      let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                    continuation.finish()
                    return
                }

                for line in content.components(separatedBy: .newlines) {
                    if Task.isCancelled { continuation.finish(); return }
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        continuation.yield(trimmed)
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Keyword Generator

    /// Takes user-supplied keywords and generates thousands of mutations.
    static func keywordGen(keywords: [String]) -> AsyncStream<String> {
        return AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                let mutations = Self.generateMutations(from: keywords)
                for candidate in mutations {
                    if Task.isCancelled { continuation.finish(); return }
                    continuation.yield(candidate)
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Mutation Engine

    private static func generateMutations(from keywords: [String]) -> [String] {
        var seen = Set<String>()
        var results: [String] = []

        func add(_ s: String) {
            guard !s.isEmpty, !seen.contains(s) else { return }
            seen.insert(s)
            results.append(s)
        }

        let specials: [Character] = ["!", "@", "#", "$", "%", "&", "*", "?"]
        let years = (2018...2026).map { String($0) }
        let commonSuffixes = ["123", "1234", "12345", "!", "!!", "1", "01", "007", "69", "99", "00"]

        for keyword in keywords {
            let lower = keyword.lowercased()
            let upper = keyword.uppercased()
            let capitalized = keyword.prefix(1).uppercased() + keyword.dropFirst().lowercased()
            let reversed = String(keyword.reversed())

            // Base forms
            add(lower)
            add(upper)
            add(capitalized)
            add(reversed)
            add(String(reversed.prefix(1)).uppercased() + reversed.dropFirst().lowercased())

            // Digit suffixes
            for i in 0...9 { add(lower + "\(i)") ; add(capitalized + "\(i)") }
            for i in 0...99 { add(lower + String(format: "%02d", i)) }
            for suffix in commonSuffixes { add(lower + suffix); add(capitalized + suffix); add(upper + suffix) }
            for year in years { add(lower + year); add(capitalized + year); add(year + lower) }

            // Special char suffixes
            for ch in specials { add(lower + String(ch)); add(capitalized + String(ch)) }

            // Leet speak
            let leet = leetSpeak(lower)
            add(leet)
            add(String(leet.prefix(1)).uppercased() + leet.dropFirst())
            for suffix in commonSuffixes { add(leet + suffix) }

            // Toggle case patterns
            add(toggleCase(lower))
        }

        // Combine pairs of keywords
        if keywords.count >= 2 {
            for i in 0..<keywords.count {
                for j in 0..<keywords.count where i != j {
                    let a = keywords[i].lowercased()
                    let b = keywords[j].lowercased()
                    let capA = a.prefix(1).uppercased() + a.dropFirst()
                    let capB = b.prefix(1).uppercased() + b.dropFirst()

                    add(a + b)
                    add(capA + capB)
                    add(a + "_" + b)
                    add(a + "." + b)
                    add(a + b + "123")
                    add(capA + capB + "!")
                    add(a + "@" + b)
                    for year in years { add(a + b + year); add(capA + capB + year) }
                }
            }
        }

        return results
    }

    private static func leetSpeak(_ input: String) -> String {
        let map: [Character: Character] = [
            "a": "4", "e": "3", "i": "1", "o": "0",
            "s": "5", "t": "7", "l": "1", "g": "9",
        ]
        return String(input.map { map[$0] ?? $0 })
    }

    private static func toggleCase(_ input: String) -> String {
        return String(input.enumerated().map { i, ch in
            i % 2 == 0 ? Character(ch.uppercased()) : Character(ch.lowercased())
        })
    }
}
