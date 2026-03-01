import Foundation

enum SimpleYAMLError: LocalizedError {
    case unsupportedSequence(line: Int)
    case invalidLine(line: Int, contents: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSequence(let line):
            return "SimpleYAML does not support sequence syntax (- item). Offending line: \(line)."
        case .invalidLine(let line, let contents):
            return "Could not parse YAML line \(line): \(contents)"
        }
    }
}

enum SimpleYAML {
    static func parseFile(at url: URL) throws -> [String: Any] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parse(text)
    }

    static func parse(_ text: String) throws -> [String: Any] {
        let root = YAMLNode()
        var stack: [(indent: Int, node: YAMLNode)] = [(-1, root)]

        let lines = text.components(separatedBy: .newlines)
        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            if trimmed.hasPrefix("-") {
                throw SimpleYAMLError.unsupportedSequence(line: lineIndex + 1)
            }

            let indent = line.prefix { $0 == " " }.count
            guard let (rawKey, rawValue) = splitKeyAndValue(from: trimmed) else {
                throw SimpleYAMLError.invalidLine(line: lineIndex + 1, contents: line)
            }

            while stack.count > 1, let last = stack.last, indent <= last.indent {
                stack.removeLast()
            }

            let key = rawKey.trimmingCharacters(in: .whitespaces)
            let parent = stack[stack.count - 1].node

            if let rawValue {
                let value = parseScalar(rawValue)
                parent.values[key] = value
                if let child = value as? YAMLNode {
                    stack.append((indent, child))
                }
            } else {
                let child = YAMLNode()
                parent.values[key] = child
                stack.append((indent, child))
            }
        }

        return toDictionary(root)
    }

    static func dictionary(_ source: [String: Any], path: [String]) -> [String: Any]? {
        var current: Any = source
        for key in path {
            guard let dictionary = current as? [String: Any], let next = dictionary[key] else {
                return nil
            }
            current = next
        }
        return current as? [String: Any]
    }

    static func string(_ source: [String: Any], path: [String]) -> String? {
        value(source, path: path) as? String
    }

    static func int(_ source: [String: Any], path: [String]) -> Int? {
        if let value = value(source, path: path) as? Int {
            return value
        }
        if let value = value(source, path: path) as? String {
            return Int(value)
        }
        return nil
    }

    static func bool(_ source: [String: Any], path: [String]) -> Bool? {
        if let value = value(source, path: path) as? Bool {
            return value
        }
        if let value = value(source, path: path) as? String {
            return Bool(value)
        }
        return nil
    }

    static func value(_ source: [String: Any], path: [String]) -> Any? {
        var current: Any = source
        for key in path {
            guard let dictionary = current as? [String: Any], let next = dictionary[key] else {
                return nil
            }
            current = next
        }
        return current
    }

    private static func splitKeyAndValue(from line: String) -> (String, String?)? {
        let characters = Array(line)
        var separatorIndex: Int?

        for index in characters.indices {
            guard characters[index] == ":" else {
                continue
            }
            let nextIndex = index + 1
            if nextIndex == characters.count || characters[nextIndex].isWhitespace {
                separatorIndex = index
                break
            }
        }

        guard let separatorIndex else {
            return nil
        }

        let key = String(characters[..<separatorIndex])
        let remainderStart = separatorIndex + 1
        if remainderStart >= characters.count {
            return (key, nil)
        }

        let value = String(characters[remainderStart...]).trimmingCharacters(in: .whitespaces)
        if value.isEmpty {
            return (key, nil)
        }

        return (key, value)
    }

    private static func parseScalar(_ raw: String) -> Any {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        if trimmed == "{}" {
            return YAMLNode()
        }

        if trimmed == "null" || trimmed == "~" {
            return NSNull()
        }

        if trimmed == "true" {
            return true
        }
        if trimmed == "false" {
            return false
        }

        if let intValue = Int(trimmed) {
            return intValue
        }
        if let doubleValue = Double(trimmed) {
            return doubleValue
        }

        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
            (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast())
        }

        return trimmed
    }

    private static func toDictionary(_ node: YAMLNode) -> [String: Any] {
        var dictionary: [String: Any] = [:]
        for (key, value) in node.values {
            if let child = value as? YAMLNode {
                dictionary[key] = toDictionary(child)
            } else {
                dictionary[key] = value
            }
        }
        return dictionary
    }
}

private final class YAMLNode {
    var values: [String: Any] = [:]
}
