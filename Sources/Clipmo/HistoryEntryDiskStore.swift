// 履歴 entry のディスク I/O だけを担当する層です。
// 保存形式の詳細をここへ閉じ込めて、ClipboardHistoryStore からは運用ルールだけが見えるようにします。
import AppKit
import Foundation
import ImageIO

final class HistoryEntryDiskStore {
    private struct FileReferenceManifest: Codable {
        let fileURLs: [String]
    }

    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let fileLayout: HistoryEntryFileLayout

    init(fileManager: FileManager = .default, fileLayout: HistoryEntryFileLayout) {
        self.fileManager = fileManager
        self.fileLayout = fileLayout
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    /// append 前にだけディレクトリ存在を保証して、通常の read path は軽く保ちます。
    func ensureDirectoryExists(_ directoryURL: URL) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
    }

    func loadEntries(from directoryURL: URL) -> [HistoryEntry] {
        let fileURLs: [URL]
        do {
            fileURLs = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        return fileURLs
            .compactMap(loadEntry(from:))
            .sorted { $0.sortKey > $1.sortKey }
    }

    /// payload ごとの差分はここで吸収し、上位層は「何を保存するか」だけを決めます。
    func write(_ payload: HistoryEntryPayload, to directoryURL: URL, baseName: String, batchIndex: Int) throws {
        let itemBaseName = fileLayout.itemBaseName(baseName: baseName, batchIndex: batchIndex)

        switch payload {
        case .text(let text):
            try text.write(
                to: fileLayout.textFileURL(in: directoryURL, itemBaseName: itemBaseName),
                atomically: true,
                encoding: .utf8
            )

        case .fileURLs(let fileURLs):
            let manifest = FileReferenceManifest(fileURLs: fileURLs)
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(
                to: fileLayout.fileReferenceManifestURL(in: directoryURL, itemBaseName: itemBaseName),
                options: .atomic
            )

        case .image(let payload):
            let imageData = try Data(contentsOf: payload.fileURL)
            let snapshot = ClipboardImageSnapshot(
                pasteboardType: payload.pasteboardType,
                data: imageData,
                width: payload.width,
                height: payload.height,
                contentHash: payload.contentHash
            )
            try snapshot.data.write(
                to: fileLayout.imageFileURL(
                    in: directoryURL,
                    itemBaseName: itemBaseName,
                    pasteboardType: snapshot.pasteboardType
                ),
                options: .atomic
            )
        }
    }

    /// clipboard から直で取った image だけは、まだ HistoryEntryPayload に包み直さず保存した方が素直です。
    func write(_ item: CapturedHistoryItem, to directoryURL: URL, baseName: String, batchIndex: Int) throws {
        switch item {
        case .text(let text):
            try write(HistoryEntryPayload.text(text), to: directoryURL, baseName: baseName, batchIndex: batchIndex)
        case .fileURLs(let fileURLs):
            try write(HistoryEntryPayload.fileURLs(fileURLs), to: directoryURL, baseName: baseName, batchIndex: batchIndex)
        case .image(let snapshot):
            let itemBaseName = fileLayout.itemBaseName(baseName: baseName, batchIndex: batchIndex)
            try snapshot.data.write(
                to: fileLayout.imageFileURL(
                    in: directoryURL,
                    itemBaseName: itemBaseName,
                    pasteboardType: snapshot.pasteboardType
                ),
                options: .atomic
            )
        }
    }

    func removeEntries(_ entries: [HistoryEntry], failureMessage: String) {
        for entry in entries {
            do {
                try fileManager.removeItem(at: entry.fileURL)
            } catch {
                print("\(failureMessage): \(error)")
            }
        }
    }

    private func loadEntry(from fileURL: URL) -> HistoryEntry? {
        guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
              values.isRegularFile == true,
              let sortKey = fileLayout.sortKey(for: fileURL)
        else {
            return nil
        }

        let payload: HistoryEntryPayload
        switch fileLayout.storageKind(for: fileURL) {
        case .text:
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return nil
            }
            payload = .text(text)

        case .fileReference:
            guard
                let manifestData = try? Data(contentsOf: fileURL),
                let manifest = try? decoder.decode(FileReferenceManifest.self, from: manifestData),
                !manifest.fileURLs.isEmpty
            else {
                return nil
            }
            payload = .fileURLs(manifest.fileURLs)

        case .image(let pasteboardType):
            guard let imageData = try? Data(contentsOf: fileURL) else {
                return nil
            }
            let dimensions = imageDimensions(for: fileURL)
            payload = .image(
                StoredImagePayload(
                    pasteboardType: pasteboardType,
                    fileURL: fileURL,
                    width: dimensions.width,
                    height: dimensions.height,
                    contentHash: ClipboardCaptureService.contentHash(for: imageData)
                )
            )

        case .unknown:
            return nil
        }

        return HistoryEntry(
            sortKey: sortKey,
            fileURL: fileURL,
            timestamp: values.contentModificationDate,
            payload: payload
        )
    }

    private func imageDimensions(for fileURL: URL) -> (width: Int?, height: Int?) {
        guard
            let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return (nil, nil)
        }

        return (
            properties[kCGImagePropertyPixelWidth] as? Int,
            properties[kCGImagePropertyPixelHeight] as? Int
        )
    }
}
