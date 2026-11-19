import Foundation

/// A tiny HTML reader. It only pulls out headings, paragraphs and list items,
/// which is all the WSDOT page needs.
struct Block: Equatable {
    enum Kind: String { case h2, h3, p, li }
    var kind: Kind
    var text: String
    var href: String?
}

enum HTML {
    static func blocks(in html: String) -> [Block] {
        let pattern = #"<(h2|h3|p|li)\b[^>]*>(.*?)</\1>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let ns = html as NSString
        return re.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let tag = ns.substring(with: m.range(at: 1)).lowercased()
            let inner = ns.substring(with: m.range(at: 2))
            let text = plainText(inner)
            guard let kind = Block.Kind(rawValue: tag), !text.isEmpty else { return nil }
            return Block(kind: kind, text: text, href: firstHref(inner))
        }
    }

    static func plainText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&rsquo;": "'", "&lsquo;": "'", "&ldquo;": "\"", "&rdquo;": "\"",
            "&ndash;": "–", "&mdash;": "—", "&lt;": "<", "&gt;": ">",
        ]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstHref(_ html: String) -> String? {
        guard let r = html.range(of: #"href="([^"]+)""#, options: .regularExpression) else { return nil }
        return String(html[r]).dropFirst(6).dropLast().description
    }
}
