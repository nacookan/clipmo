// 自動ペーストに必要なアクセシビリティ権限の確認だけを切り出した窓口です。
import ApplicationServices
import Foundation

enum AccessibilityPermissions {
    /// 権限が既に通っているかだけを軽く確認します。
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 初回起動時に設定画面への導線を出して、後続の貼り付け失敗を減らします。
    static func promptIfNeeded() {
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
