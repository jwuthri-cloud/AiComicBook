import Foundation

/// Finds glossary terms inside page text so they can be highlighted and tapped.
final class TermMatcher {
    struct Match {
        let range: Range<String.Index>
        let termId: String
    }

    private let caseSensitive: NSRegularExpression?
    private let caseInsensitive: NSRegularExpression?
    private var lookup: [String: String] = [:]

    init(terms: [Term]) {
        var sensitive: [String] = []
        var insensitive: [String] = []
        for term in terms {
            let names = ([term.term] + term.aka)
                .map { $0.replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression) }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count >= 2 }
            for name in Set(names) {
                lookup[Self.key(name)] = term.id
                let pattern = NSRegularExpression.escapedPattern(for: name)
                    .replacingOccurrences(of: "\\ ", with: "[\\s-]+")
                    .replacingOccurrences(of: " ", with: "[\\s-]+")
                if name == name.uppercased() && name.count <= 6 {
                    sensitive.append(pattern)
                } else {
                    insensitive.append(pattern)
                }
            }
        }
        func build(_ patterns: [String], _ options: NSRegularExpression.Options) -> NSRegularExpression? {
            guard !patterns.isEmpty else { return nil }
            let sorted = patterns.sorted { $0.count > $1.count }
            return try? NSRegularExpression(pattern: "(?<![\\w-])(?:\(sorted.joined(separator: "|")))(?:s|es)?(?![\\w-])", options: options)
        }
        caseSensitive = build(sensitive, [])
        caseInsensitive = build(insensitive, [.caseInsensitive])
    }

    static func key(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func termId(for matched: String) -> String? {
        let k = Self.key(matched)
        if let id = lookup[k] { return id }
        for suffix in ["es", "s"] where k.hasSuffix(suffix) {
            if let id = lookup[String(k.dropLast(suffix.count))] { return id }
        }
        return nil
    }

    /// Non-overlapping matches, longest term wins, each term at most once (`seen` is shared across a page).
    func matches(in text: String, seen: inout Set<String>, excluding: Set<String> = []) -> [Match] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var candidates: [NSRange] = []
        for regex in [caseInsensitive, caseSensitive].compactMap({ $0 }) {
            candidates += regex.matches(in: text, range: full).map(\.range)
        }
        candidates.sort { $0.length != $1.length ? $0.length > $1.length : $0.location < $1.location }

        var taken: [NSRange] = []
        var result: [Match] = []
        for r in candidates {
            guard !taken.contains(where: { NSIntersectionRange($0, r).length > 0 }),
                  let id = termId(for: ns.substring(with: r)),
                  !seen.contains(id), !excluding.contains(id),
                  let range = Range(r, in: text)
            else { continue }
            taken.append(r)
            seen.insert(id)
            result.append(Match(range: range, termId: id))
        }
        return result.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}
