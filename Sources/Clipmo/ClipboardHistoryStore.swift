// 履歴運用の調停役です。
// ディスク形式の詳細は専用クラスへ寄せて、ここでは重複除去と保持ポリシーの整合だけを扱います。
import Foundation

final class ClipboardHistoryStore {
    private var directoryURL: URL
    private let fileLayout: HistoryEntryFileLayout
    private let diskStore: HistoryEntryDiskStore
    private var retentionPolicy: HistoryRetentionPolicy = .unlimited

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        let fileLayout = HistoryEntryFileLayout()
        self.fileLayout = fileLayout
        self.diskStore = HistoryEntryDiskStore(fileManager: fileManager, fileLayout: fileLayout)
    }

    /// 履歴フォルダは config で差し替えられるので、runtime で追従可能にしています。
    func updateDirectoryURL(_ directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    /// Dropbox 共有時の衝突回避のため、端末ごとの短い ID をファイル名へ埋め込みます。
    func updateDeviceIdentifier(_ deviceIdentifier: String) {
        fileLayout.updateDeviceIdentifier(deviceIdentifier)
    }

    func updateRetentionPolicy(_ retentionPolicy: HistoryRetentionPolicy) {
        self.retentionPolicy = retentionPolicy
        pruneExpiredEntries()
    }

    func entries() -> [HistoryEntry] {
        pruneExpiredEntries()
        return diskStore.loadEntries(from: directoryURL)
    }

    func append(_ text: String, maxItemCount: Int) {
        appendBatch([HistoryEntryPayload.text(text)], maxItemCount: maxItemCount)
    }

    func append(_ payload: HistoryEntryPayload, maxItemCount: Int) {
        appendBatch([payload], maxItemCount: maxItemCount)
    }

    func append(_ item: CapturedHistoryItem, maxItemCount: Int) {
        appendBatch([item], maxItemCount: maxItemCount)
    }

    /// append 系はすべて batch 保存へ寄せて、重複除去と件数制限を一箇所で扱います。
    func appendBatch(_ items: [CapturedHistoryItem], maxItemCount: Int) {
        let validItems = items.filter(isValidCapturedItem)
        guard !validItems.isEmpty else {
            return
        }

        do {
            try diskStore.ensureDirectoryExists(directoryURL)
        } catch {
            print("Clipmo: 履歴ディレクトリの作成に失敗しました: \(error)")
            return
        }

        pruneExpiredEntries()
        let existingEntries = diskStore.loadEntries(from: directoryURL)
        let duplicateEntries = existingEntries.filter { entry in
            validItems.contains { isDuplicate(capturedItem: $0, against: entry.payload) }
        }
        let batchBaseName = fileLayout.nextBatchBaseName()

        do {
            for (index, item) in validItems.enumerated() {
                try diskStore.write(item, to: directoryURL, baseName: batchBaseName, batchIndex: index + 1)
            }
            diskStore.removeEntries(duplicateEntries, failureMessage: "Clipmo: 重複履歴の削除に失敗しました")
            enforceLimit(maxItemCount)
        } catch {
            print("Clipmo: 履歴の保存に失敗しました: \(error)")
        }
    }

    func appendBatch(_ payloads: [HistoryEntryPayload], maxItemCount: Int) {
        let validPayloads = payloads.filter(isValidPayload)
        guard !validPayloads.isEmpty else {
            return
        }

        do {
            try diskStore.ensureDirectoryExists(directoryURL)
        } catch {
            print("Clipmo: 履歴ディレクトリの作成に失敗しました: \(error)")
            return
        }

        pruneExpiredEntries()
        let existingEntries = diskStore.loadEntries(from: directoryURL)
        let duplicateEntries = existingEntries.filter { entry in
            validPayloads.contains { $0.isDuplicate(of: entry.payload) }
        }
        let batchBaseName = fileLayout.nextBatchBaseName()

        do {
            for (index, payload) in validPayloads.enumerated() {
                try diskStore.write(payload, to: directoryURL, baseName: batchBaseName, batchIndex: index + 1)
            }
            diskStore.removeEntries(duplicateEntries, failureMessage: "Clipmo: 重複履歴の削除に失敗しました")
            enforceLimit(maxItemCount)
        } catch {
            print("Clipmo: 履歴の保存に失敗しました: \(error)")
        }
    }

    /// 古い entry を先に消してから数を数えることで、保持期間と件数制限をぶつけずに運用します。
    func enforceLimit(_ maxItemCount: Int) {
        guard maxItemCount > 0 else {
            return
        }

        pruneExpiredEntries()
        let loadedEntries = diskStore.loadEntries(from: directoryURL)
        guard loadedEntries.count > maxItemCount else {
            return
        }

        let overflowEntries = Array(loadedEntries.dropFirst(maxItemCount))
        diskStore.removeEntries(overflowEntries, failureMessage: "Clipmo: 古い履歴の削除に失敗しました")
    }

    /// メニュー表示や保存のたびに掃除する運用にして、独立 timer を持たずに単純化しています。
    private func pruneExpiredEntries(referenceDate: Date = Date()) {
        guard let expirationDate = retentionPolicy.expirationDate(referenceDate: referenceDate) else {
            return
        }

        let expiredEntries = diskStore.loadEntries(from: directoryURL).filter { entry in
            guard let timestamp = entry.timestamp else {
                return false
            }

            return timestamp < expirationDate
        }

        diskStore.removeEntries(expiredEntries, failureMessage: "Clipmo: 期限切れ履歴の削除に失敗しました")
    }

    private func isValidPayload(_ payload: HistoryEntryPayload) -> Bool {
        switch payload {
        case .text(let text):
            return !text.isEmpty
        case .fileURLs(let fileURLs):
            return !fileURLs.isEmpty
        case .image:
            return true
        }
    }

    private func isValidCapturedItem(_ item: CapturedHistoryItem) -> Bool {
        switch item {
        case .text(let text):
            return !text.isEmpty
        case .fileURLs(let fileURLs):
            return !fileURLs.isEmpty
        case .image:
            return true
        }
    }

    private func isDuplicate(capturedItem: CapturedHistoryItem, against payload: HistoryEntryPayload) -> Bool {
        switch (capturedItem, payload) {
        case (.text(let lhs), .text(let rhs)):
            return lhs == rhs
        case (.fileURLs(let lhs), .fileURLs(let rhs)):
            return lhs == rhs
        case (.image(let lhs), .image(let rhs)):
            return lhs.contentHash == rhs.contentHash && lhs.pasteboardType == rhs.pasteboardType
        default:
            return false
        }
    }
}
