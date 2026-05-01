// この端末だけの短い ID を永続化して、共有履歴ファイル名の衝突を避けます。
import Foundation

final class DeviceIdentityStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    /// 一度作った ID は固定して、履歴ファイル名の並びと由来がぶれないようにします。
    func loadOrCreate() -> String {
        if let existing = load(), !existing.isEmpty {
            return existing
        }

        let identifier = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        save(identifier)
        return identifier
    }

    private func load() -> String? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save(_ identifier: String) {
        let directoryURL = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        try? identifier.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
