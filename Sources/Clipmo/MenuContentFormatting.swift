// メニュー項目の見た目とツールチップ文字列だけをまとめた helper です。
// `MenuContentBuilder` から表示整形の細部を外し、構造の組み立てに集中させます。
import AppKit

@MainActor
final class MenuContentFormatting {
    private let snippetRenderer: SnippetRenderer
    private let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    init(snippetRenderer: SnippetRenderer) {
        self.snippetRenderer = snippetRenderer
    }

    func previewText(for text: String, accessKeyLabel: String, historyPreviewMaxWidth: CGFloat) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let preview = collapsed.isEmpty ? L10n.text("menu.preview.blank") : collapsed
        let prefix = accessKeyLabel.isEmpty ? "" : "\(accessKeyLabel). "
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0)]
        let availableWidth = max(40, historyPreviewMaxWidth - renderedWidth(of: prefix, attributes: attributes))

        guard renderedWidth(of: preview, attributes: attributes) > availableWidth else {
            return preview
        }

        let ellipsis = "..."
        guard renderedWidth(of: ellipsis, attributes: attributes) <= availableWidth else {
            return ellipsis
        }

        let characters = Array(preview)
        var low = 0
        var high = characters.count

        while low < high {
            let mid = (low + high + 1) / 2
            let candidate = String(characters.prefix(mid)) + ellipsis

            if renderedWidth(of: candidate, attributes: attributes) <= availableWidth {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return String(characters.prefix(low)) + ellipsis
    }

    func historyTooltipText(for entry: HistoryEntry) -> String {
        let timestampText = entry.timestamp.map { tooltipDateFormatter.string(from: $0) } ?? L10n.text("menu.tooltip.unknownTimestamp")

        switch entry.payload {
        case .text(let text):
            return [
                timestampText,
                historyCountLine(for: text),
                "--",
                text
            ].joined(separator: "\n")

        case .fileURLs(let fileURLs):
            return [
                timestampText,
                fileTooltipSummary(for: fileURLs),
                "--",
                fileURLs.joined(separator: "\n")
            ].joined(separator: "\n")

        case .image(let image):
            return [
                timestampText,
                imageTooltipSummary(for: image),
                "--",
                L10n.text("menu.tooltip.imageData")
            ].joined(separator: "\n")
        }
    }

    func snippetTooltipText(for content: SnippetContent) -> String {
        snippetRenderer.render(content.text, mode: content.renderMode)
    }

    func customTransformTooltipText(for transform: CustomTransform) -> String {
        [
            L10n.format("menu.tooltip.transform.pattern", transform.pattern),
            L10n.format("menu.tooltip.transform.replacement", transform.replacement)
        ].joined(separator: "\n")
    }

    func historyPreviewSourceText(for payload: HistoryEntryPayload) -> String {
        switch payload {
        case .text(let text):
            return text
        case .fileURLs(let fileURLs):
            guard let firstPath = fileURLs.first else {
                return L10n.text("menu.preview.file.empty")
            }

            let firstName = URL(fileURLWithPath: firstPath).lastPathComponent
            if fileURLs.count == 1 {
                return L10n.format("menu.preview.file.single", firstName)
            }

            return L10n.format("menu.preview.file.multiple", fileURLs.count, firstName)

        case .image(let image):
            return "[\(imageTooltipSummary(for: image))]"
        }
    }

    func fileTooltipSummary(for fileURLs: [String]) -> String {
        L10n.format("menu.tooltip.fileCount", fileURLs.count)
    }

    func imageTooltipSummary(for image: StoredImagePayload) -> String {
        var parts = [L10n.text("menu.tooltip.image")]

        let format = imageFormatName(for: image.pasteboardType)
        if !format.isEmpty {
            parts.append(format)
        }

        if let width = image.width, let height = image.height {
            parts.append("\(width)x\(height)")
        }

        return parts.joined(separator: " ")
    }

    func attributedFolderTitle(for title: String) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // `NSMenuItem.image` を使うと menu 全体に画像カラムができて、
        // 通常の履歴項目まで同じだけ右へ寄ってしまうので attributedTitle で埋めています。
        if let folderImage = NSImage(systemSymbolName: "folder", accessibilityDescription: title) {
            folderImage.isTemplate = true
            folderImage.size = NSSize(width: 13, height: 13)

            let attachment = NSTextAttachment()
            attachment.image = folderImage

            let imageString = NSMutableAttributedString(attachment: attachment)
            imageString.addAttribute(.baselineOffset, value: -1, range: NSRange(location: 0, length: imageString.length))
            result.append(imageString)
            result.append(NSAttributedString(string: " "))
        }

        result.append(NSAttributedString(string: title))
        return result
    }

    private func renderedWidth(of string: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        (string as NSString).size(withAttributes: attributes).width
    }

    private func historyCountLine(for text: String) -> String {
        guard text.count == 1 else {
            return L10n.format("menu.tooltip.textCount", text.count)
        }

        let unicodeScalars = text.unicodeScalars.map { scalar in
            String(format: "U+%04X", scalar.value)
        }.joined(separator: " ")
        let utf8Bytes = text.utf8.map { byte in
            String(format: "%02X", byte)
        }.joined(separator: " ")

        return L10n.format("menu.tooltip.singleCharacterDetail", unicodeScalars, utf8Bytes)
    }

    private func imageFormatName(for pasteboardType: String) -> String {
        switch pasteboardType {
        case NSPasteboard.PasteboardType.png.rawValue:
            return "PNG"
        case NSPasteboard.PasteboardType.tiff.rawValue:
            return "TIFF"
        case "public.jpeg":
            return "JPEG"
        default:
            return ""
        }
    }
}
