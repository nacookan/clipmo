// App 内の表示文言を Localizable.strings から引く最小ヘルパーです。
// 文字列キーを一箇所に寄せるより、呼び出し元でキーを明示した方が追いやすい方針にしています。
import Foundation

enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
