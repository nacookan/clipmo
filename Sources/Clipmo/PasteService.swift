// clipboard への書き込みと、前面 app への `Command+V` 送信だけを担当します。
// timing 調整が多いので、貼り付けの不安定さはここへ閉じ込めます。
import AppKit

@MainActor
final class PasteService {
    private let pasteboard: NSPasteboard
    private let activationPollInterval: TimeInterval = 0.03
    private let activationPollAttempts = 30

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// text は一番単純な form なので string type にだけ書き込みます。
    func setClipboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 履歴 payload の kind ごとに、貼り戻し可能な pasteboard type へ復元します。
    @discardableResult
    func setClipboard(_ entry: HistoryEntry) -> Bool {
        switch entry.payload {
        case .text(let text):
            setClipboard(text)
            return true

        case .fileURLs(let paths):
            let urls = paths.map { URL(fileURLWithPath: $0) }
            pasteboard.clearContents()
            return pasteboard.writeObjects(urls as [NSURL])

        case .image(let payload):
            guard let data = try? Data(contentsOf: payload.fileURL) else {
                NSSound.beep()
                return false
            }

            pasteboard.clearContents()
            return pasteboard.setData(data, forType: NSPasteboard.PasteboardType(payload.pasteboardType))
        }
    }

    /// 貼り付けは clipboard 更新と前面復帰の二段階に分け、menu close と干渉しないよう async へ逃がします。
    func copyAndPaste(_ text: String, targetApplication: NSRunningApplication?) {
        setClipboard(text)

        guard AccessibilityPermissions.isTrusted else {
            NSSound.beep()
            return
        }

        DispatchQueue.main.async {
            self.restoreFocusAndPaste(targetApplication: targetApplication)
        }
    }

    @discardableResult
    func copyAndPaste(_ entry: HistoryEntry, targetApplication: NSRunningApplication?) -> Bool {
        guard setClipboard(entry) else {
            return false
        }

        guard AccessibilityPermissions.isTrusted else {
            NSSound.beep()
            return false
        }

        DispatchQueue.main.async {
            self.restoreFocusAndPaste(targetApplication: targetApplication)
        }

        return true
    }

    /// 送信先 app がまだ frontmost でない場合は、短い polling で待ってから `Command+V` を打ちます。
    private func restoreFocusAndPaste(targetApplication: NSRunningApplication?) {
        let currentApplication = NSRunningApplication.current

        guard let targetApplication,
              targetApplication.processIdentifier != currentApplication.processIdentifier else {
            schedulePaste(after: 0.05)
            return
        }

        if NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApplication.processIdentifier {
            schedulePaste(after: 0.03)
            return
        }

        requestActivation(for: targetApplication, from: currentApplication)
        waitForActivationAndPaste(targetApplication: targetApplication, remainingAttempts: activationPollAttempts)
    }

    private func requestActivation(for targetApplication: NSRunningApplication, from currentApplication: NSRunningApplication) {
        if currentApplication.isActive {
            NSApp.yieldActivation(to: targetApplication)
            _ = targetApplication.activate(from: currentApplication, options: [])
        } else {
            _ = targetApplication.activate(options: [])
        }
    }

    private func waitForActivationAndPaste(targetApplication: NSRunningApplication, remainingAttempts: Int) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApplication.processIdentifier {
            schedulePaste(after: 0.03)
            return
        }

        guard remainingAttempts > 0 else {
            schedulePaste(after: 0.12)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + activationPollInterval) {
            if remainingAttempts == self.activationPollAttempts / 2 {
                self.requestActivation(for: targetApplication, from: NSRunningApplication.current)
            }

            self.waitForActivationAndPaste(
                targetApplication: targetApplication,
                remainingAttempts: remainingAttempts - 1
            )
        }
    }

    private func schedulePaste(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.sendCommandV()
        }
    }

    private func sendCommandV() {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
