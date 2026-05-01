// `clipmo.conf` の TOML 読み書きを担当します。
// 設定ファイルは人が直接編集する前提なので、コメント付きで書き出しつつ、読み込み側は壊れた行をできるだけ読み飛ばします。
import Foundation

private enum ConfigTOMLValue {
    case string(String)
    case integer(Int)
    case double(Double)
    case stringArray([String])
}

enum ConfigTOMLCodec {
    static func decode(_ data: Data) -> AppConfig? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        var values: [String: ConfigTOMLValue] = [:]
        var currentSection: String?

        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let uncommentedLine = stripComment(from: String(rawLine))
            let line = uncommentedLine.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                let sectionName = String(line.dropFirst().dropLast()).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                currentSection = sectionName.isEmpty ? nil : sectionName
                continue
            }

            guard let separatorIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<separatorIndex]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let valueText = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !key.isEmpty, let value = parseValue(String(valueText)) else {
                continue
            }

            let keyPath = currentSection.map { "\($0).\(key)" } ?? key
            values[keyPath] = value
        }

        var config = AppConfig.default

        if let key = stringValue(for: "hotKey.key", in: values) {
            config.hotKey.key = key
        }
        if let modifiers = modifierArrayValue(for: "hotKey.modifiers", in: values) {
            config.hotKey.modifiers = modifiers
        }

        if let copyOnly = modifierValue(for: "itemSelectionModifiers.copyOnly", in: values) {
            config.itemSelectionModifiers.copyOnly = copyOnly
        }
        if let revealInFinder = modifierValue(for: "itemSelectionModifiers.revealInFinder", in: values) {
            config.itemSelectionModifiers.revealInFinder = revealInFinder
        }
        if let repeatSelection = modifierValue(for: "itemSelectionModifiers.repeatSelection", in: values) {
            config.itemSelectionModifiers.repeatSelection = repeatSelection
        }

        if let ocrLanguages = stringArrayValue(for: "ocrLanguages", in: values) {
            config.ocrLanguages = ocrLanguages
        }
        if let menuRotation = stringArrayValue(for: "hotKeyMenuRotation", in: values) {
            config.hotKeyMenuRotation = menuRotation
        }

        if let historyDirectory = stringValue(for: "directories.history", in: values) {
            config.directories.history = historyDirectory
        }
        if let snippetsDirectory = stringValue(for: "directories.snippets", in: values) {
            config.directories.snippets = snippetsDirectory
        }
        if let transformsDirectory = stringValue(for: "directories.transforms", in: values) {
            config.directories.transforms = transformsDirectory
        }

        if let retentionUnit = stringValue(for: "historyRetention.unit", in: values),
           let unit = HistoryRetentionPolicy.Unit(rawValue: retentionUnit) {
            config.historyRetention.unit = unit
        }
        if let retentionValue = integerValue(for: "historyRetention.value", in: values) {
            config.historyRetention.value = retentionValue
        }

        if let maxHistoryCount = integerValue(for: "maxHistoryCount", in: values) {
            config.maxHistoryCount = maxHistoryCount
        }
        if let menuPreviewMaxWidth = doubleValue(for: "menuPreviewMaxWidth", in: values) {
            config.menuPreviewMaxWidth = menuPreviewMaxWidth
        }
        if let historyItemsPerMenuLevel = integerValue(for: "historyItemsPerMenuLevel", in: values) {
            config.historyItemsPerMenuLevel = historyItemsPerMenuLevel
        }

        return config.validated()
    }

    static func encode(_ config: AppConfig) -> Data {
        renderedText(for: config).data(using: .utf8) ?? Data()
    }

    private static func renderedText(for config: AppConfig) -> String {
        let normalizedConfig = config.validated()

        var lines: [String] = [
            "# Clipmo configuration file",
            "# Paths may be absolute, start with ~/..., or be relative to ~/.clipmo.",
            ""
        ]

        lines.append("maxHistoryCount = \(normalizedConfig.maxHistoryCount)")
        lines.append("menuPreviewMaxWidth = \(tomlNumber(normalizedConfig.menuPreviewMaxWidth))")
        lines.append("historyItemsPerMenuLevel = \(normalizedConfig.historyItemsPerMenuLevel)")
        lines.append("hotKeyMenuRotation = \(tomlStringArray(normalizedConfig.hotKeyMenuRotation))")
        if normalizedConfig.ocrLanguages.isEmpty {
            lines.append("# ocrLanguages = [\"ja-JP\", \"en-US\"]")
        } else {
            lines.append("ocrLanguages = \(tomlStringArray(normalizedConfig.ocrLanguages))")
        }

        lines.append("")
        lines.append("[hotKey]")
        lines.append("key = \(tomlString(normalizedConfig.hotKey.key))")
        lines.append("modifiers = \(tomlStringArray(normalizedConfig.hotKey.modifiers.map(\.rawValue)))")

        lines.append("")
        lines.append("[itemSelectionModifiers]")
        lines.append("copyOnly = \(tomlString(normalizedConfig.itemSelectionModifiers.copyOnly.rawValue))")
        lines.append("revealInFinder = \(tomlString(normalizedConfig.itemSelectionModifiers.revealInFinder.rawValue))")
        lines.append("repeatSelection = \(tomlString(normalizedConfig.itemSelectionModifiers.repeatSelection.rawValue))")

        lines.append("")
        lines.append("[directories]")
        appendOptionalString(
            normalizedConfig.directories.history,
            key: "history",
            example: "~/Dropbox/Clipmo/history",
            into: &lines
        )
        appendOptionalString(
            normalizedConfig.directories.snippets,
            key: "snippets",
            example: "~/Dropbox/Clipmo/snippets",
            into: &lines
        )
        appendOptionalString(
            normalizedConfig.directories.transforms,
            key: "transforms",
            example: "~/Dropbox/Clipmo/transforms",
            into: &lines
        )

        lines.append("")
        lines.append("[historyRetention]")
        lines.append("unit = \(tomlString(normalizedConfig.historyRetention.unit.rawValue))")
        if let value = normalizedConfig.historyRetention.value,
           normalizedConfig.historyRetention.unit != .unlimited {
            lines.append("value = \(value)")
        } else {
            lines.append("# value = 30")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendOptionalString(_ value: String?, key: String, example: String, into lines: inout [String]) {
        if let value {
            lines.append("\(key) = \(tomlString(value))")
        } else {
            lines.append("# \(key) = \(tomlString(example))")
        }
    }

    private static func stringValue(for keyPath: String, in values: [String: ConfigTOMLValue]) -> String? {
        guard case .string(let value)? = values[keyPath] else {
            return nil
        }
        return value
    }

    private static func integerValue(for keyPath: String, in values: [String: ConfigTOMLValue]) -> Int? {
        switch values[keyPath] {
        case .integer(let value):
            return value
        case .double(let value):
            return Int(value)
        default:
            return nil
        }
    }

    private static func doubleValue(for keyPath: String, in values: [String: ConfigTOMLValue]) -> Double? {
        switch values[keyPath] {
        case .integer(let value):
            return Double(value)
        case .double(let value):
            return value
        default:
            return nil
        }
    }

    private static func stringArrayValue(for keyPath: String, in values: [String: ConfigTOMLValue]) -> [String]? {
        guard case .stringArray(let values)? = values[keyPath] else {
            return nil
        }
        return values
    }

    private static func modifierValue(for keyPath: String, in values: [String: ConfigTOMLValue]) -> ItemSelectionModifierKey? {
        guard let value = stringValue(for: keyPath, in: values) else {
            return nil
        }
        return ItemSelectionModifierKey(rawValue: value.lowercased())
    }

    private static func modifierArrayValue(for keyPath: String, in values: [String: ConfigTOMLValue]) -> [ItemSelectionModifierKey]? {
        guard let rawValues = stringArrayValue(for: keyPath, in: values) else {
            return nil
        }

        let modifiers = rawValues.compactMap { ItemSelectionModifierKey(rawValue: $0.lowercased()) }
        return modifiers.isEmpty ? nil : modifiers
    }

    private static func parseValue(_ text: String) -> ConfigTOMLValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("\"") {
            guard let string = parseStringLiteral(trimmed) else {
                return nil
            }
            return .string(string)
        }

        if trimmed.hasPrefix("[") {
            guard let stringArray = parseStringArray(trimmed) else {
                return nil
            }
            return .stringArray(stringArray)
        }

        if let integer = Int(trimmed) {
            return .integer(integer)
        }

        if let double = Double(trimmed) {
            return .double(double)
        }

        return nil
    }

    private static func parseStringArray(_ text: String) -> [String]? {
        guard text.hasPrefix("[") && text.hasSuffix("]") else {
            return nil
        }

        let innerText = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !innerText.isEmpty else {
            return []
        }

        var values: [String] = []
        var current = ""
        var inString = false
        var isEscaping = false
        var token = ""

        for character in innerText {
            if inString {
                token.append(character)
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
                token.append(character)
                continue
            }

            if character == "," {
                let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let parsed = parseStringLiteral(trimmedToken) else {
                    return nil
                }
                values.append(parsed)
                token.removeAll(keepingCapacity: true)
                continue
            }

            token.append(character)
            current.append(character)
        }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = parseStringLiteral(trimmedToken) else {
            return nil
        }
        values.append(parsed)
        _ = current
        return values
    }

    private static func parseStringLiteral(_ text: String) -> String? {
        guard text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 else {
            return nil
        }

        let innerText = text.dropFirst().dropLast()
        var result = ""
        var isEscaping = false

        for character in innerText {
            if isEscaping {
                switch character {
                case "\"":
                    result.append("\"")
                case "\\":
                    result.append("\\")
                case "t":
                    result.append("\t")
                case "n":
                    result.append("\n")
                case "r":
                    result.append("\r")
                default:
                    result.append(character)
                }
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            result.append(character)
        }

        return isEscaping ? nil : result
    }

    private static func stripComment(from line: String) -> String {
        var result = ""
        var inString = false
        var isEscaping = false

        for character in line {
            if inString {
                result.append(character)
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "#" {
                break
            }

            if character == "\"" {
                inString = true
            }

            result.append(character)
        }

        return result
    }

    private static func tomlString(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    private static func tomlStringArray(_ values: [String]) -> String {
        "[" + values.map(tomlString).joined(separator: ", ") + "]"
    }

    private static func tomlNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return String(value)
    }
}
