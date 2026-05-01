// `~/.clipmo` を起点に、設定ファイルと各ストレージの既定位置を解決するファイルです。
import Foundation

struct StorageDirectories: Equatable {
    let historyDirectory: URL
    let snippetsDirectory: URL
    let transformsDirectory: URL
}

struct AppPaths {
    let baseDirectory: URL
    let configFile: URL
    let legacyJSONConfigFile: URL
    let deviceIdentifierFile: URL
    let defaultHistoryDirectory: URL
    let defaultSnippetsDirectory: URL
    let defaultTransformsDirectory: URL

    init(fileManager: FileManager = .default) {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        baseDirectory = homeDirectory.appendingPathComponent(".clipmo", isDirectory: true)
        configFile = baseDirectory.appendingPathComponent("clipmo.conf", isDirectory: false)
        legacyJSONConfigFile = baseDirectory.appendingPathComponent("config.json", isDirectory: false)
        deviceIdentifierFile = baseDirectory.appendingPathComponent(".device-id", isDirectory: false)
        defaultHistoryDirectory = baseDirectory.appendingPathComponent("history", isDirectory: true)
        defaultSnippetsDirectory = baseDirectory.appendingPathComponent("snippets", isDirectory: true)
        defaultTransformsDirectory = baseDirectory.appendingPathComponent("transforms", isDirectory: true)
    }

    func prepare(using fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    /// storage の実配置は config で差し替えられるので、既定値と override の解決をここへ集めます。
    func storageDirectories(for config: AppConfig) -> StorageDirectories {
        StorageDirectories(
            historyDirectory: resolvedDirectoryPath(config.directories.history, fallback: defaultHistoryDirectory),
            snippetsDirectory: resolvedDirectoryPath(config.directories.snippets, fallback: defaultSnippetsDirectory),
            transformsDirectory: resolvedDirectoryPath(config.directories.transforms, fallback: defaultTransformsDirectory)
        )
    }

    func prepareStorageDirectories(_ directories: StorageDirectories, using fileManager: FileManager = .default) throws {
        for directory in [directories.historyDirectory, directories.snippetsDirectory, directories.transformsDirectory] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    private func resolvedDirectoryPath(_ rawPath: String?, fallback: URL) -> URL {
        guard let rawPath = rawPath, !rawPath.isEmpty else {
            return fallback
        }

        // 相対パスは `~/.clipmo` 基準にしておくと、Dropbox などへの切り替えも記述が短くなります。
        let expandedPath = (rawPath as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL
        }

        return baseDirectory.appendingPathComponent(expandedPath, isDirectory: true).standardizedFileURL
    }
}
