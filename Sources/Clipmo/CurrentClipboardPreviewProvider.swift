// 現在の clipboard を「メニュー上でどう見せるか」へ変換する helper です。
// 履歴表示用の整形とは別責務なので、builder 本体から分けています。
import AppKit

struct CurrentClipboardPreview {
    let signature: ClipboardContentSignature?
    let sourceText: String
    let toolTip: String
}

enum CurrentClipboardPreviewProvider {
    /// メニュー上の「現在のクリップボード」欄は、履歴 payload と同じ見せ方へ寄せておきます。
    @MainActor
    static func load(formatter: MenuContentFormatting, pasteboard: NSPasteboard = .general) -> CurrentClipboardPreview? {
        if let observation = ClipboardCaptureService.fileObservation(from: pasteboard),
           case .fileURLs(let fileURLs) = observation.primarySignature {
            return CurrentClipboardPreview(
                signature: observation.primarySignature,
                sourceText: formatter.historyPreviewSourceText(for: .fileURLs(fileURLs)),
                toolTip: fileURLs.joined(separator: "\n")
            )
        }

        if let imageSnapshot = ImageOCRService.imageSnapshot(from: pasteboard) {
            let imagePayload = StoredImagePayload(
                pasteboardType: imageSnapshot.pasteboardType,
                fileURL: URL(fileURLWithPath: "/"),
                width: imageSnapshot.width,
                height: imageSnapshot.height,
                contentHash: imageSnapshot.contentHash
            )
            return CurrentClipboardPreview(
                signature: .image(contentHash: imageSnapshot.contentHash, pasteboardType: imageSnapshot.pasteboardType),
                sourceText: formatter.historyPreviewSourceText(for: .image(imagePayload)),
                toolTip: formatter.imageTooltipSummary(for: imagePayload)
            )
        }

        guard let text = PasteboardTextResolver.preferredText(from: pasteboard), !text.isEmpty else {
            return nil
        }

        return CurrentClipboardPreview(
            signature: .text(text),
            sourceText: text,
            toolTip: text
        )
    }
}
