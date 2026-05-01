// 現在の clipboard を「履歴へどう積むか」という観点で正規化する層です。
// text / file / image の優先順位と、補助 entry を何個積むかをここで決めます。
import AppKit
import CryptoKit
import Foundation

struct ClipboardImageSnapshot: Equatable {
    let pasteboardType: String
    let data: Data
    let width: Int?
    let height: Int?
    let contentHash: String
}

enum ClipboardContentSignature: Equatable {
    case text(String)
    case fileURLs([String])
    case image(contentHash: String, pasteboardType: String)
}

enum CapturedHistoryItem {
    case text(String)
    case fileURLs([String])
    case image(ClipboardImageSnapshot)
}

struct ClipboardObservation {
    let primarySignature: ClipboardContentSignature
    let historyItems: [CapturedHistoryItem]
    let didUseOCR: Bool
}

enum ClipboardCaptureService {
    /// ファイルコピーは、貼り戻し用の file entry と、人が読めるフルパス text の両方を残します。
    static func fileObservation(from pasteboard: NSPasteboard) -> ClipboardObservation? {
        guard let filePaths = filePaths(from: pasteboard), !filePaths.isEmpty else {
            return nil
        }

        // append 順の最後が履歴の先頭になるので、
        // 補助用のフルパステキストを先に積み、本体のファイル entry を最後に置きます。
        return ClipboardObservation(
            primarySignature: .fileURLs(filePaths),
            historyItems: [
                .text(filePaths.joined(separator: "\n")),
                .fileURLs(filePaths)
            ],
            didUseOCR: false
        )
    }

    /// HTML / RTF / PDF も最終的には text へ落として、履歴 UI を単純に保ちます。
    static func textObservation(from pasteboard: NSPasteboard) -> ClipboardObservation? {
        guard let text = PasteboardTextResolver.preferredText(from: pasteboard), !text.isEmpty else {
            return nil
        }

        return ClipboardObservation(
            primarySignature: .text(text),
            historyItems: [.text(text)],
            didUseOCR: false
        )
    }

    /// 画像は本体を優先しつつ、OCR 結果があれば text entry も補助で残します。
    static func imageObservation(from snapshot: ClipboardImageSnapshot, recognizedText: String?) -> ClipboardObservation {
        let trimmedRecognizedText = recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasOCRText = !(trimmedRecognizedText?.isEmpty ?? true)

        // 画像本体を履歴先頭に残したいので、OCR テキストがある場合は先に積みます。
        var items: [CapturedHistoryItem] = []
        if let trimmedRecognizedText, !trimmedRecognizedText.isEmpty {
            items.append(.text(trimmedRecognizedText))
        }
        items.append(.image(snapshot))

        return ClipboardObservation(
            primarySignature: .image(contentHash: snapshot.contentHash, pasteboardType: snapshot.pasteboardType),
            historyItems: items,
            didUseOCR: hasOCRText
        )
    }

    static func contentHash(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func filePaths(from pasteboard: NSPasteboard) -> [String]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL],
              !urls.isEmpty else {
            return nil
        }

        return urls.map { ($0 as URL).path }
    }
}
