// snippets ディレクトリを再帰的に読み込み、menu 表示用の tree に変換します。
// `.clipmo-snippet` だけ動的展開対象にして、通常ファイルとの役割を分けます。
import Foundation

struct SnippetContent {
    let text: String
    let renderMode: SnippetRenderMode
    let sourceFileURL: URL
}

enum SnippetNode {
    case folder(name: String, children: [SnippetNode])
    case item(name: String, content: SnippetContent, timestamp: Date?)
}

final class SnippetLoader {
    private let dynamicSnippetSuffix = ".clipmo-snippet"
    private var rootDirectory: URL
    private let fileManager: FileManager
    private let candidateEncodings: [String.Encoding] = [
        .utf8,
        .utf16,
        .utf16LittleEndian,
        .utf16BigEndian,
        .shiftJIS
    ]

    init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func updateRootDirectory(_ rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    /// menu 構造はフォルダ階層をそのまま反映させるので、再帰で tree を組み立てます。
    func load() -> [SnippetNode] {
        loadContents(of: rootDirectory)
    }

    private func loadContents(of directory: URL) -> [SnippetNode] {
        let itemURLs: [URL]
        do {
            itemURLs = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        return itemURLs
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .compactMap { itemURL in
                guard let values = try? itemURL.resourceValues(
                    forKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey]
                ) else {
                    return nil
                }

                if values.isDirectory == true {
                    return .folder(
                        name: itemURL.lastPathComponent,
                        children: loadContents(of: itemURL)
                    )
                }

                guard values.isRegularFile == true, let text = loadText(from: itemURL) else {
                    return nil
                }

                return .item(
                    name: displayName(for: itemURL),
                    content: SnippetContent(
                        text: text,
                        renderMode: renderMode(for: itemURL),
                        sourceFileURL: itemURL
                    ),
                    timestamp: values.contentModificationDate
                )
            }
    }

    /// 動的スニペットだけ拡張子を隠し、通常ファイルは一般的な拡張子除去で十分とします。
    private func displayName(for url: URL) -> String {
        let filename = url.lastPathComponent
        if filename.lowercased().hasSuffix(dynamicSnippetSuffix) {
            let endIndex = filename.index(filename.endIndex, offsetBy: -dynamicSnippetSuffix.count)
            let name = String(filename[..<endIndex])
            return name.isEmpty ? filename : name
        }

        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? url.lastPathComponent : name
    }

    private func renderMode(for url: URL) -> SnippetRenderMode {
        url.lastPathComponent.lowercased().hasSuffix(dynamicSnippetSuffix) ? .clipmoTemplate : .plainText
    }

    private func loadText(from url: URL) -> String? {
        for encoding in candidateEncodings {
            if let text = try? String(contentsOf: url, encoding: encoding) {
                return text
            }
        }

        return nil
    }
}
