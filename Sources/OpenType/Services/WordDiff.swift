import Foundation

/// Word-level diff using LCS (Longest Common Subsequence) to detect corrections.
enum WordDiff {

    struct Replacement: Sendable {
        let original: String
        let corrected: String
    }

    /// Detect word-level replacements between original and corrected text.
    static func detectReplacements(original: String, corrected: String) -> [Replacement] {
        let origWords = original.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let corrWords = corrected.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        guard !origWords.isEmpty && !corrWords.isEmpty else { return [] }

        // LCS table
        let m = origWords.count
        let n = corrWords.count
        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if origWords[i - 1].lowercased() == corrWords[j - 1].lowercased() {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find replacements
        var replacements: [Replacement] = []
        var i = m, j = n
        var pendingOrig: [String] = []
        var pendingCorr: [String] = []

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && origWords[i - 1].lowercased() == corrWords[j - 1].lowercased() {
                // Flush any pending replacement
                if !pendingOrig.isEmpty && !pendingCorr.isEmpty {
                    let orig = pendingOrig.reversed().joined(separator: " ")
                    let corr = pendingCorr.reversed().joined(separator: " ")
                    replacements.append(Replacement(original: orig, corrected: corr))
                }
                pendingOrig.removeAll()
                pendingCorr.removeAll()
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                pendingCorr.append(corrWords[j - 1])
                j -= 1
            } else {
                pendingOrig.append(origWords[i - 1])
                i -= 1
            }
        }

        // Flush remaining
        if !pendingOrig.isEmpty && !pendingCorr.isEmpty {
            let orig = pendingOrig.reversed().joined(separator: " ")
            let corr = pendingCorr.reversed().joined(separator: " ")
            replacements.append(Replacement(original: orig, corrected: corr))
        }

        // Filter: skip trivial replacements (same word, single char, pure punctuation)
        return replacements.filter { r in
            r.original.lowercased() != r.corrected.lowercased() &&
            r.corrected.count >= 2 &&
            r.corrected.rangeOfCharacter(from: .letters) != nil
        }
    }
}
