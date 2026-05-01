// 履歴ファイルの命名規則と、拡張子から type を読み戻す規則をまとめた層です。
// Finder から見たときの分かりやすさと、Dropbox 共有時の衝突回避をここで両立させます。
import AppKit
import Foundation

final class HistoryEntryFileLayout {
    enum StorageKind {
        case text
        case fileReference
        case image(String)
        case unknown
    }

    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSSSSS'Z'"
        return formatter
    }()

    private var deviceIdentifier = "device000"
    private var lastIssuedDate = Date.distantPast

    /// 端末 ID はファイル名を短く保ちたいので、ここで一度だけ正規化して使い回します。
    func updateDeviceIdentifier(_ deviceIdentifier: String) {
        let normalized = deviceIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        self.deviceIdentifier = normalized.isEmpty ? "device000" : normalized
    }

    /// 同一端末で連続保存した batch も衝突しないよう、前回より必ず 1 microsecond 以上進めます。
    func nextBatchBaseName(referenceDate: Date = Date()) -> String {
        let minimumNextDate = lastIssuedDate.addingTimeInterval(0.000001)
        let issuedDate = max(referenceDate, minimumNextDate)
        lastIssuedDate = issuedDate
        return "\(timestampFormatter.string(from: issuedDate))-\(deviceIdentifier)"
    }

    /// 1 回の clipboard 変化から複数 entry を作るので、batch 内連番を末尾へ付けます。
    func itemBaseName(baseName: String, batchIndex: Int) -> String {
        "\(baseName)-\(String(format: "%02d", batchIndex))"
    }

    func textFileURL(in directoryURL: URL, itemBaseName: String) -> URL {
        directoryURL.appendingPathComponent("\(itemBaseName).txt", isDirectory: false)
    }

    func fileReferenceManifestURL(in directoryURL: URL, itemBaseName: String) -> URL {
        directoryURL.appendingPathComponent("\(itemBaseName).file.manifest.json", isDirectory: false)
    }

    /// 画像は Finder からそのまま見えた方が扱いやすいので、bin ではなく実拡張子を使います。
    func imageFileURL(in directoryURL: URL, itemBaseName: String, pasteboardType: String) -> URL {
        let fileExtension = imageFileExtension(for: pasteboardType)
        return directoryURL.appendingPathComponent("\(itemBaseName).\(fileExtension)", isDirectory: false)
    }

    func storageKind(for fileURL: URL) -> StorageKind {
        let fileName = fileURL.lastPathComponent

        if fileName.hasSuffix(".txt") {
            return .text
        }

        if fileName.hasSuffix(".file.manifest.json") {
            return .fileReference
        }

        switch fileURL.pathExtension.lowercased() {
        case "png":
            return .image(NSPasteboard.PasteboardType.png.rawValue)
        case "tif", "tiff":
            return .image(NSPasteboard.PasteboardType.tiff.rawValue)
        case "jpg", "jpeg":
            return .image("public.jpeg")
        default:
            return .unknown
        }
    }

    /// sortKey は拡張子の違いを吸収して、時系列ソートだけに使える基底名へ戻します。
    func sortKey(for fileURL: URL) -> String? {
        let fileName = fileURL.lastPathComponent

        if fileName.hasSuffix(".file.manifest.json") {
            return String(fileName.dropLast(".file.manifest.json".count))
        }

        if fileName.hasSuffix(".txt") {
            return String(fileName.dropLast(".txt".count))
        }

        if case .image = storageKind(for: fileURL) {
            return fileURL.deletingPathExtension().lastPathComponent
        }

        return nil
    }

    private func imageFileExtension(for pasteboardType: String) -> String {
        switch pasteboardType {
        case NSPasteboard.PasteboardType.png.rawValue:
            return "png"
        case NSPasteboard.PasteboardType.tiff.rawValue:
            return "tiff"
        case "public.jpeg":
            return "jpg"
        default:
            return "img"
        }
    }
}
