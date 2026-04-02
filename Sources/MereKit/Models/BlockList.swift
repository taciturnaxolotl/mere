import Foundation

/// A parsed, engine-agnostic block list.
public struct BlockList: Sendable {

    public struct Rule: Sendable {
        public enum Action: Sendable { case block, allowList }
        public enum ResourceType: String, Sendable, CaseIterable {
            case document, script, image, stylesheet = "style-sheet"
            case font, media, raw, svg = "svg-document"
            case xhr = "fetch", websocket, other
        }

        public let urlPattern: String       // regex
        public let action: Action
        public let resourceTypes: Set<ResourceType>
        public let ifDomain: [String]       // only apply on these domains
        public let unlessDomain: [String]   // skip on these domains

        public init(
            urlPattern: String,
            action: Action = .block,
            resourceTypes: Set<ResourceType> = [],
            ifDomain: [String] = [],
            unlessDomain: [String] = []
        ) {
            self.urlPattern = urlPattern
            self.action = action
            self.resourceTypes = resourceTypes
            self.ifDomain = ifDomain
            self.unlessDomain = unlessDomain
        }
    }

    public let name: String
    public let rules: [Rule]
    public let updatedAt: Date

    public init(name: String, rules: [Rule], updatedAt: Date = .now) {
        self.name = name
        self.rules = rules
        self.updatedAt = updatedAt
    }

    /// Total count of blocking rules (excludes allowlist entries).
    public var blockCount: Int { rules.filter { $0.action == .block }.count }
}

// MARK: - EasyList parser

/// Parses a subset of Adblock Plus / EasyList filter syntax into BlockList.Rules.
///
/// Supported syntax:
///   - `||example.com^`             → domain anchor
///   - `@@||example.com^`           → allowlist
///   - `$script,image`              → resource type options
///   - `$domain=foo.com|~bar.com`   → domain restrictions
///   - `/regex/`                    → regex rule
///   - `##` cosmetic rules          → ignored (CSS injection, not request blocking)
public enum EasyListParser {

    public static func parse(_ text: String, name: String) -> BlockList {
        var rules: [BlockList.Rule] = []

        for line in text.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)

            // Skip comments, headers, empty lines, cosmetic rules
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") || line.contains("##") || line.contains("#@#") {
                continue
            }

            if let rule = parseRule(line) {
                rules.append(rule)
            }
        }

        return BlockList(name: name, rules: rules)
    }

    private static func parseRule(_ line: String) -> BlockList.Rule? {
        var raw = line
        let isAllowList = raw.hasPrefix("@@")
        if isAllowList { raw = String(raw.dropFirst(2)) }

        // Split options after `$`
        var options: [String] = []
        var pattern = raw
        if let dollarIdx = raw.lastIndex(of: "$"), !raw.hasPrefix("/") {
            let optStr = String(raw[raw.index(after: dollarIdx)...])
            // Only treat as options if it looks like options (no spaces, known keywords)
            if !optStr.contains(" ") {
                options = optStr.components(separatedBy: ",")
                pattern = String(raw[..<dollarIdx])
            }
        }

        // Skip purely cosmetic/script-inject options
        let skipOptions = ["elemhide", "generichide", "genericblock", "jsinject", "content", "extension", "stealth"]
        if options.contains(where: { skipOptions.contains($0) }) { return nil }

        // Parse resource types
        var resourceTypes: Set<BlockList.Rule.ResourceType> = []
        var ifDomain: [String] = []
        var unlessDomain: [String] = []

        for opt in options {
            if opt.hasPrefix("domain=") {
                let domains = String(opt.dropFirst(7)).components(separatedBy: "|")
                for d in domains {
                    if d.hasPrefix("~") { unlessDomain.append(String(d.dropFirst())) }
                    else if !d.isEmpty { ifDomain.append(d) }
                }
            } else if let rt = parseResourceType(opt) {
                resourceTypes.insert(rt)
            }
        }

        // Convert EasyList pattern to regex
        guard let regex = patternToRegex(pattern) else { return nil }

        return BlockList.Rule(
            urlPattern: regex,
            action: isAllowList ? .allowList : .block,
            resourceTypes: resourceTypes,
            ifDomain: ifDomain,
            unlessDomain: unlessDomain
        )
    }

    private static func parseResourceType(_ opt: String) -> BlockList.Rule.ResourceType? {
        switch opt {
        case "script":      return .script
        case "image":       return .image
        case "stylesheet":  return .stylesheet
        case "font":        return .font
        case "media":       return .media
        case "xmlhttprequest", "fetch": return .xhr
        case "websocket":   return .websocket
        case "document":    return .document
        case "subdocument": return .raw
        case "other":       return .other
        default:            return nil
        }
    }

    private static func patternToRegex(_ pattern: String) -> String? {
        // Already a regex
        if pattern.hasPrefix("/") && pattern.hasSuffix("/") {
            let inner = String(pattern.dropFirst().dropLast())
            return inner.isEmpty ? nil : inner
        }

        var p = pattern

        // Domain anchor `||` → match start of host
        let domainAnchor = p.hasPrefix("||")
        if domainAnchor { p = String(p.dropFirst(2)) }

        // Left anchor `|` → start of URL
        let leftAnchor = !domainAnchor && p.hasPrefix("|")
        if leftAnchor { p = String(p.dropFirst()) }

        // Right anchor `|`
        let rightAnchor = p.hasSuffix("|")
        if rightAnchor { p = String(p.dropLast()) }

        if p.isEmpty { return nil }

        // Escape regex metacharacters except `*` and `^`
        var escaped = ""
        for ch in p {
            switch ch {
            case ".", "+", "?", "{", "}", "(", ")", "[", "]", "\\", "$":
                escaped += "\\\(ch)"
            case "*":
                escaped += ".*"
            case "^":
                // Separator — matches any non-word boundary character or end of string
                escaped += "([^a-zA-Z0-9.%-]|$)"
            default:
                escaped += String(ch)
            }
        }

        // Apply anchors
        if domainAnchor {
            escaped = "https?://(www\\.)?" + escaped
        } else if leftAnchor {
            escaped = "^" + escaped
        }
        if rightAnchor { escaped += "$" }

        return escaped
    }
}
