// `clipmo.conf` の設定モデルと、壊れた入力の補正ルールをまとめたファイルです。
// UI を持たない app なので、コメント付き TOML を人が手で編集しやすいことを重視します。
import Foundation

enum ItemSelectionModifierKey: String, Codable, CaseIterable {
    case command
    case option
    case control
    case shift
}

struct ItemSelectionModifierConfiguration: Codable, Equatable {
    var copyOnly: ItemSelectionModifierKey
    var revealInFinder: ItemSelectionModifierKey
    var repeatSelection: ItemSelectionModifierKey

    private enum CodingKeys: String, CodingKey {
        case copyOnly
        case revealInFinder
        case repeatSelection
    }

    static let `default` = ItemSelectionModifierConfiguration(
        copyOnly: .shift,
        revealInFinder: .option,
        repeatSelection: .command
    )

    /// modifier は役割ごとに一意である方が直感的なので、衝突時はここで自動補正します。
    func validated() -> ItemSelectionModifierConfiguration {
        var used = Set<ItemSelectionModifierKey>()

        let validatedCopyOnly = uniqueModifier(
            preferred: copyOnly,
            used: &used,
            fallbacks: [.shift, .option, .command, .control]
        )
        let validatedRevealInFinder = uniqueModifier(
            preferred: revealInFinder,
            used: &used,
            fallbacks: [.option, .command, .shift, .control]
        )
        let validatedRepeatSelection = uniqueModifier(
            preferred: repeatSelection,
            used: &used,
            fallbacks: [.command, .shift, .option, .control]
        )

        return ItemSelectionModifierConfiguration(
            copyOnly: validatedCopyOnly,
            revealInFinder: validatedRevealInFinder,
            repeatSelection: validatedRepeatSelection
        )
    }

    private func uniqueModifier(
        preferred: ItemSelectionModifierKey,
        used: inout Set<ItemSelectionModifierKey>,
        fallbacks: [ItemSelectionModifierKey]
    ) -> ItemSelectionModifierKey {
        if used.insert(preferred).inserted {
            return preferred
        }

        for fallback in fallbacks where used.insert(fallback).inserted {
            return fallback
        }

        return preferred
    }

    init(copyOnly: ItemSelectionModifierKey, revealInFinder: ItemSelectionModifierKey, repeatSelection: ItemSelectionModifierKey) {
        self.copyOnly = copyOnly
        self.revealInFinder = revealInFinder
        self.repeatSelection = repeatSelection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        copyOnly = (try? container.decode(ItemSelectionModifierKey.self, forKey: .copyOnly)) ?? Self.default.copyOnly
        revealInFinder = (try? container.decode(ItemSelectionModifierKey.self, forKey: .revealInFinder)) ?? Self.default.revealInFinder
        repeatSelection = (try? container.decode(ItemSelectionModifierKey.self, forKey: .repeatSelection)) ?? Self.default.repeatSelection
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(copyOnly, forKey: .copyOnly)
        try container.encode(revealInFinder, forKey: .revealInFinder)
        try container.encode(repeatSelection, forKey: .repeatSelection)
    }
}

struct StorageDirectoryOverrides: Codable, Equatable {
    var history: String?
    var snippets: String?
    var transforms: String?

    static let `default` = StorageDirectoryOverrides()

    func validated() -> StorageDirectoryOverrides {
        StorageDirectoryOverrides(
            history: Self.normalized(history),
            snippets: Self.normalized(snippets),
            transforms: Self.normalized(transforms)
        )
    }

    var isDefault: Bool {
        history == nil && snippets == nil && transforms == nil
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct HistoryRetentionPolicy: Codable, Equatable {
    enum Unit: String, Codable {
        case unlimited
        case hours
        case days
    }

    var unit: Unit
    var value: Int?

    static let unlimited = HistoryRetentionPolicy(unit: .unlimited, value: nil)

    init(unit: Unit, value: Int? = nil) {
        self.unit = unit
        self.value = value
    }

    func validated() -> HistoryRetentionPolicy {
        switch unit {
        case .unlimited:
            return .unlimited
        case .hours, .days:
            return HistoryRetentionPolicy(unit: unit, value: max(1, value ?? 1))
        }
    }

    func expirationDate(referenceDate: Date, calendar: Calendar = .current) -> Date? {
        switch unit {
        case .unlimited:
            return nil
        case .hours:
            return calendar.date(byAdding: .hour, value: -(value ?? 1), to: referenceDate)
        case .days:
            return calendar.date(byAdding: .day, value: -(value ?? 1), to: referenceDate)
        }
    }
}

struct AppConfig: Codable, Equatable {
    var hotKey: HotKeyConfiguration
    var itemSelectionModifiers: ItemSelectionModifierConfiguration
    var ocrLanguages: [String]
    var hotKeyMenuRotation: [String]
    var directories: StorageDirectoryOverrides
    var historyRetention: HistoryRetentionPolicy
    var maxHistoryCount: Int
    var menuPreviewMaxWidth: Double
    var historyItemsPerMenuLevel: Int

    private enum CodingKeys: String, CodingKey {
        case hotKey
        case itemSelectionModifiers
        case ocrLanguages
        case hotKeyMenuRotation
        case directories
        case historyRetention
        case maxHistoryCount
        case menuPreviewMaxWidth
        case historyItemsPerMenuLevel
    }

    static let `default` = AppConfig(
        hotKey: .default,
        itemSelectionModifiers: .default,
        ocrLanguages: [],
        hotKeyMenuRotation: ["all"],
        directories: .default,
        historyRetention: .unlimited,
        maxHistoryCount: 100,
        menuPreviewMaxWidth: 420,
        historyItemsPerMenuLevel: 20
    )

    init(
        hotKey: HotKeyConfiguration,
        itemSelectionModifiers: ItemSelectionModifierConfiguration,
        ocrLanguages: [String],
        hotKeyMenuRotation: [String],
        directories: StorageDirectoryOverrides,
        historyRetention: HistoryRetentionPolicy,
        maxHistoryCount: Int,
        menuPreviewMaxWidth: Double,
        historyItemsPerMenuLevel: Int
    ) {
        self.hotKey = hotKey
        self.itemSelectionModifiers = itemSelectionModifiers
        self.ocrLanguages = ocrLanguages
        self.hotKeyMenuRotation = hotKeyMenuRotation
        self.directories = directories
        self.historyRetention = historyRetention
        self.maxHistoryCount = maxHistoryCount
        self.menuPreviewMaxWidth = menuPreviewMaxWidth
        self.historyItemsPerMenuLevel = historyItemsPerMenuLevel
    }

    /// 読めなかった項目だけ既定値へ戻し、他は生かす方針で config 破損に強くします。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotKey = (try? container.decode(HotKeyConfiguration.self, forKey: .hotKey)) ?? .default
        itemSelectionModifiers = (try? container.decode(ItemSelectionModifierConfiguration.self, forKey: .itemSelectionModifiers)) ?? .default
        ocrLanguages = (try? container.decode([String].self, forKey: .ocrLanguages)) ?? []
        hotKeyMenuRotation = (try? container.decode([String].self, forKey: .hotKeyMenuRotation)) ?? AppConfig.default.hotKeyMenuRotation
        directories = (try? container.decode(StorageDirectoryOverrides.self, forKey: .directories)) ?? .default
        historyRetention = (try? container.decode(HistoryRetentionPolicy.self, forKey: .historyRetention)) ?? .unlimited
        maxHistoryCount = (try? container.decode(Int.self, forKey: .maxHistoryCount)) ?? AppConfig.default.maxHistoryCount
        menuPreviewMaxWidth = (try? container.decode(Double.self, forKey: .menuPreviewMaxWidth)) ?? AppConfig.default.menuPreviewMaxWidth
        historyItemsPerMenuLevel = (try? container.decode(Int.self, forKey: .historyItemsPerMenuLevel)) ?? AppConfig.default.historyItemsPerMenuLevel
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hotKey, forKey: .hotKey)
        try container.encode(itemSelectionModifiers, forKey: .itemSelectionModifiers)
        if !ocrLanguages.isEmpty {
            try container.encode(ocrLanguages, forKey: .ocrLanguages)
        }
        try container.encode(hotKeyMenuRotation, forKey: .hotKeyMenuRotation)
        if !directories.isDefault {
            try container.encode(directories, forKey: .directories)
        }
        if historyRetention != .unlimited {
            try container.encode(historyRetention, forKey: .historyRetention)
        }
        try container.encode(maxHistoryCount, forKey: .maxHistoryCount)
        try container.encode(menuPreviewMaxWidth, forKey: .menuPreviewMaxWidth)
        try container.encode(historyItemsPerMenuLevel, forKey: .historyItemsPerMenuLevel)
    }

    /// 起動不能よりは安全側の既定値へ丸める方を優先します。
    func validated() -> AppConfig {
        AppConfig(
            hotKey: hotKey.validated(),
            itemSelectionModifiers: itemSelectionModifiers.validated(),
            ocrLanguages: Self.normalizedLanguageIdentifiers(ocrLanguages),
            hotKeyMenuRotation: HotKeyMenuScope.validatedConfigNames(from: hotKeyMenuRotation),
            directories: directories.validated(),
            historyRetention: historyRetention.validated(),
            maxHistoryCount: max(1, maxHistoryCount),
            menuPreviewMaxWidth: max(120, menuPreviewMaxWidth),
            historyItemsPerMenuLevel: max(1, historyItemsPerMenuLevel)
        )
    }

    private static func normalizedLanguageIdentifiers(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        return identifiers.compactMap { rawIdentifier in
            let trimmed = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            let normalized = Locale.identifier(.bcp47, from: trimmed).replacingOccurrences(of: "_", with: "-")
            guard seen.insert(normalized).inserted else {
                return nil
            }

            return normalized
        }
    }
}

struct HotKeyConfiguration: Codable, Equatable {
    var key: String
    var modifiers: [ItemSelectionModifierKey]

    static let `default` = HotKeyConfiguration(
        key: "v",
        modifiers: [.option, .control]
    )

    func validated() -> HotKeyConfiguration {
        let normalizedKey = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return HotKeyConfiguration(
            key: normalizedKey,
            modifiers: normalizedModifiers(modifiers)
        )
    }

    private func normalizedModifiers(_ modifiers: [ItemSelectionModifierKey]) -> [ItemSelectionModifierKey] {
        var seen = Set<ItemSelectionModifierKey>()
        return modifiers.filter { seen.insert($0).inserted }
    }
}

final class ConfigStore {
    private struct FileSignature: Equatable {
        let modificationDate: Date?
        let size: UInt64?
    }

    private let paths: AppPaths
    private let fileManager: FileManager
    private let legacyDecoder = JSONDecoder()
    private var lastSignature: FileSignature?

    init(paths: AppPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func prepareEnvironment() throws {
        try paths.prepare(using: fileManager)

        guard !fileManager.fileExists(atPath: paths.configFile.path) else {
            return
        }

        if try migrateLegacyConfigIfNeeded() {
            return
        }

        try writeDefaultConfig()
    }

    func loadInitialConfig() -> AppConfig {
        do {
            try prepareEnvironment()
        } catch {
            print("Clipmo: 初期ディレクトリの作成に失敗しました: \(error)")
        }

        lastSignature = currentSignature()
        return readConfigFromDisk() ?? .default
    }

    func reloadIfNeeded() -> AppConfig? {
        let signature = currentSignature()
        guard signature != lastSignature else {
            return nil
        }

        lastSignature = signature
        return readConfigFromDisk()
    }

    private func writeDefaultConfig() throws {
        let data = ConfigTOMLCodec.encode(AppConfig.default)
        try data.write(to: paths.configFile, options: .atomic)
    }

    private func readConfigFromDisk() -> AppConfig? {
        do {
            let data = try Data(contentsOf: paths.configFile)
            return ConfigTOMLCodec.decode(data)
        } catch {
            print("Clipmo: clipmo.conf の読み込みに失敗したため既存設定を維持します: \(error)")
            return nil
        }
    }

    /// 設定ファイル名の変更で既存利用者の設定を失わないよう、旧 JSON は一度だけ TOML へ移行します。
    private func migrateLegacyConfigIfNeeded() throws -> Bool {
        guard fileManager.fileExists(atPath: paths.legacyJSONConfigFile.path) else {
            return false
        }

        do {
            let data = try Data(contentsOf: paths.legacyJSONConfigFile)
            let decoded = try legacyDecoder.decode(AppConfig.self, from: data).validated()
            let encoded = ConfigTOMLCodec.encode(decoded)
            try encoded.write(to: paths.configFile, options: .atomic)
            return true
        } catch {
            print("Clipmo: 旧 config.json の移行に失敗したため既定設定を作成します: \(error)")
            return false
        }
    }

    private func currentSignature() -> FileSignature? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: paths.configFile.path) else {
            return nil
        }

        return FileSignature(
            modificationDate: attributes[.modificationDate] as? Date,
            size: (attributes[.size] as? NSNumber)?.uint64Value
        )
    }
}
