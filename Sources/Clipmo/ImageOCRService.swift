// 画像データから OCR を行う小さなラッパです。
// Finder でのファイルコピーは対象外にして、画像本体が clipboard にある時だけ動かします。
import AppKit
import ImageIO
import Vision

enum ImageOCRService {
    /// file URL より前に拾わないよう、画像本体だけを素直に抜き出します。
    static func imageSnapshot(from pasteboard: NSPasteboard) -> ClipboardImageSnapshot? {
        // Finder でのファイルコピーは file URL として先に解決される前提なので、
        // ここでは「画像データそのもの」が載っている clipboard だけを対象にします。
        for type in supportedPasteboardTypes {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                let dimensions = imageDimensions(from: data)
                return ClipboardImageSnapshot(
                    pasteboardType: type.rawValue,
                    data: data,
                    width: dimensions.width,
                    height: dimensions.height,
                    contentHash: ClipboardCaptureService.contentHash(for: data)
                )
            }
        }

        return nil
    }

    /// OCR は utility task へ逃がして、menu 操作や polling を詰まらせないようにします。
    static func recognizeText(from imageData: Data, preferredLanguageIdentifiers: [String] = []) async -> String? {
        await Task.detached(priority: .utility) {
            guard
                let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                return nil
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = true
            }

            let recognitionLanguages = resolvedRecognitionLanguages(
                for: request,
                preferredLanguageIdentifiers: preferredLanguageIdentifiers
            )
            if !recognitionLanguages.isEmpty {
                request.recognitionLanguages = recognitionLanguages
            }

            do {
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                try handler.perform([request])
            } catch {
                print("Clipmo OCR failed: \(error.localizedDescription)")
                return nil
            }

            let lines = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !lines.isEmpty else {
                return nil
            }

            return lines.joined(separator: "\n")
        }.value
    }

    private static let supportedPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.jpeg")
    ]

    private static func resolvedRecognitionLanguages(
        for request: VNRecognizeTextRequest,
        preferredLanguageIdentifiers: [String]
    ) -> [String] {
        let preferredIdentifiers = preferredLanguageIdentifiers.isEmpty ? Locale.preferredLanguages : preferredLanguageIdentifiers
        guard !preferredIdentifiers.isEmpty else {
            return []
        }

        let supportedIdentifiers = Set((try? request.supportedRecognitionLanguages()) ?? [])
        guard !supportedIdentifiers.isEmpty else {
            return preferredIdentifiers
        }

        var resolved: [String] = []
        var seen = Set<String>()

        for identifier in preferredIdentifiers {
            let normalized = Locale.identifier(.bcp47, from: identifier).replacingOccurrences(of: "_", with: "-")
            guard !normalized.isEmpty else {
                continue
            }

            let baseLanguage = normalized.split(separator: "-").first.map(String.init) ?? normalized
            let matchedIdentifier =
                supportedIdentifiers.first(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame })
                ?? supportedIdentifiers.first(where: { $0.caseInsensitiveCompare(baseLanguage) == .orderedSame })
                ?? supportedIdentifiers.first(where: { $0.lowercased().hasPrefix(baseLanguage.lowercased() + "-") })

            guard let matchedIdentifier, seen.insert(matchedIdentifier).inserted else {
                continue
            }

            resolved.append(matchedIdentifier)
        }

        return resolved
    }

    private static func imageDimensions(from data: Data) -> (width: Int?, height: Int?) {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
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
