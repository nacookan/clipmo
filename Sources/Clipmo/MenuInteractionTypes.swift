// メニュー操作まわりで共有する、表示元と選択モードの共通定義です。
// UI 構築側とイベント制御側の双方から参照するため、単独ファイルへ分けています。
import AppKit

enum MenuPresentation {
    case statusItem
    case hotKey(HotKeyMenuScope)
}

enum ClipboardItemSelectionMode {
    case paste
    case copyOnly
    case revealInFinder
    case repeatSelection
}

extension ItemSelectionModifierKey {
    var cgEventFlag: CGEventFlags {
        switch self {
        case .command:
            return .maskCommand
        case .option:
            return .maskAlternate
        case .control:
            return .maskControl
        case .shift:
            return .maskShift
        }
    }
}
