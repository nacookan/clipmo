// 履歴 entry を UI 層と保存層のあいだで受け渡す共有モデルです。
// text / file / image を同じ型で扱えるようにして、各層が保存形式を意識しないで済むようにしています。
import Foundation

struct StoredImagePayload: Equatable {
    let pasteboardType: String
    let fileURL: URL
    let width: Int?
    let height: Int?
    let contentHash: String
}

enum HistoryEntryPayload: Equatable {
    case text(String)
    case fileURLs([String])
    case image(StoredImagePayload)

    /// 履歴の見た目ではなく、同一 clipboard 内容かどうかを判定するための代表値です。
    var primarySignature: ClipboardContentSignature {
        switch self {
        case .text(let text):
            return .text(text)
        case .fileURLs(let fileURLs):
            return .fileURLs(fileURLs)
        case .image(let payload):
            return .image(contentHash: payload.contentHash, pasteboardType: payload.pasteboardType)
        }
    }

    /// 重複排除は payload の意味的な一致だけを見て、保存ファイル名や timestamp には依存させません。
    func isDuplicate(of other: HistoryEntryPayload) -> Bool {
        switch (self, other) {
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

struct HistoryEntry {
    let sortKey: String
    let fileURL: URL
    let timestamp: Date?
    let payload: HistoryEntryPayload
}
