// clipboard から text を取り出す時の優先順位を統一する helper です。
// HTML / RTF / PDF は書式を捨てて plain text に落とします。
import AppKit
import PDFKit

enum PasteboardTextResolver {
    /// plain text が最優先で、なければ rich text 系を text 化して使います。
    static func preferredText(from pasteboard: NSPasteboard) -> String? {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return richText(from: pasteboard)
        }

        return text
    }

    private static func richText(from pasteboard: NSPasteboard) -> String? {
        if let htmlData = pasteboard.data(forType: .html),
           let text = attributedStringText(from: htmlData, documentType: .html),
           !text.isEmpty {
            return text
        }

        if let rtfData = pasteboard.data(forType: .rtf),
           let text = attributedStringText(from: rtfData, documentType: .rtf),
           !text.isEmpty {
            return text
        }

        if let pdfData = pasteboard.data(forType: .pdf),
           let text = PDFDocument(data: pdfData)?.string,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        return nil
    }

    private static func attributedStringText(from data: Data, documentType: NSAttributedString.DocumentType) -> String? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: documentType
        ]

        return try? NSAttributedString(data: data, options: options, documentAttributes: nil).string
    }
}
