// menu 選択や監視イベントを、履歴追加・clipboard 書き換え・HUD 表示へまとめる orchestration 層です。
// UI 側と永続化側の間に置いて、副作用の順序を一箇所で固定します。
import AppKit

@MainActor
final class ClipboardWorkflowController {
    private let historyStore: ClipboardHistoryStore
    private let snippetRenderer: SnippetRenderer
    private let transformStore: TransformStore
    private let clipboardMonitor: ClipboardMonitor
    private let pasteService: PasteService
    private let hudMessageController: HUDMessageController
    private let pasteboard: NSPasteboard

    init(
        historyStore: ClipboardHistoryStore,
        snippetRenderer: SnippetRenderer,
        transformStore: TransformStore,
        clipboardMonitor: ClipboardMonitor,
        pasteService: PasteService,
        hudMessageController: HUDMessageController,
        pasteboard: NSPasteboard = .general
    ) {
        self.historyStore = historyStore
        self.snippetRenderer = snippetRenderer
        self.transformStore = transformStore
        self.clipboardMonitor = clipboardMonitor
        self.pasteService = pasteService
        self.hudMessageController = hudMessageController
        self.pasteboard = pasteboard
    }

    /// 監視から来た observation は履歴化だけに絞り、変換や貼り付けは明示操作だけに限定します。
    func handleObservedClipboardContent(_ observation: ClipboardObservation, maxHistoryCount: Int) {
        // 監視時は履歴化だけに絞り、変換はすべて明示的なメニュー操作で行います。
        historyStore.appendBatch(observation.historyItems, maxItemCount: maxHistoryCount)

        if observation.didUseOCR {
            hudMessageController.show(message: L10n.text("hud.ocrCompleted"))
        }
    }

    /// 履歴選択は mode ごとに分岐しますが、MRU 先頭へ上げる判断はここで共通化します。
    func handleHistorySelection(
        _ entry: HistoryEntry,
        mode: ClipboardItemSelectionMode,
        maxHistoryCount: Int,
        targetApplication: NSRunningApplication?
    ) {
        switch mode {
        case .revealInFinder:
            revealInFinder(entry)
        case .paste, .copyOnly, .repeatSelection:
            // 履歴から再選択した項目も、MRU の先頭へ明示的に押し上げます。
            historyStore.append(entry.payload, maxItemCount: maxHistoryCount)

            switch entry.payload {
            case .text(let text):
                switch mode {
                case .paste, .repeatSelection:
                    copyAndPaste(text, targetApplication: targetApplication)
                case .copyOnly:
                    copyOnly(text)
                case .revealInFinder:
                    break
                }

            case .fileURLs, .image:
                switch mode {
                case .paste, .repeatSelection:
                    copyAndPaste(entry, targetApplication: targetApplication)
                case .copyOnly:
                    copyOnly(entry)
                case .revealInFinder:
                    break
                }
            }
        }
    }

    /// スニペットは render 後の最終 text を履歴化して扱います。
    func handleSnippetSelection(
        _ content: SnippetContent,
        mode: ClipboardItemSelectionMode,
        maxHistoryCount: Int,
        targetApplication: NSRunningApplication?
    ) {
        let text = snippetRenderer.render(content.text, mode: content.renderMode)

        switch mode {
        case .paste, .repeatSelection:
            // スニペットは監視経由ではなく明示操作で clipboard を書き換えるので、
            // 貼り付けでもコピーのみでもここで履歴へ追加しておきます。
            historyStore.append(text, maxItemCount: maxHistoryCount)
            copyAndPaste(text, targetApplication: targetApplication)
        case .copyOnly:
            historyStore.append(text, maxItemCount: maxHistoryCount)
            copyOnly(text)
        case .revealInFinder:
            revealInFinder(content)
        }
    }

    func applyBuiltInTransformToClipboard(identifier: String, maxHistoryCount: Int) {
        applyTransformToClipboard(maxHistoryCount: maxHistoryCount) { [transformStore] text in
            transformStore.applyBuiltInTransform(identifier: identifier, to: text)
        }
    }

    func applyCustomTransformToClipboard(identifier: String, maxHistoryCount: Int) {
        applyTransformToClipboard(maxHistoryCount: maxHistoryCount) { [transformStore] text in
            transformStore.applyCustomTransform(identifier: identifier, to: text)
        }
    }

    /// 変換は clipboard 上の text だけを対象にして、元の text も一緒に履歴へ残します。
    private func applyTransformToClipboard(
        maxHistoryCount: Int,
        applying transform: (String) -> TransformApplicationResult?
    ) {
        guard let clipboardText = PasteboardTextResolver.preferredText(from: pasteboard) else {
            NSSound.beep()
            return
        }

        guard let result = transform(clipboardText) else {
            NSSound.beep()
            return
        }

        guard result.didChange else {
            NSSound.beep()
            return
        }

        // 手動変換では、直前の元テキストも履歴に残しておくと
        // 「変換したけど元に戻したい」をメニュー上でそのまま辿れます。
        historyStore.appendBatch(
            [HistoryEntryPayload.text(clipboardText), HistoryEntryPayload.text(result.output)],
            maxItemCount: maxHistoryCount
        )
        suppressNextClipboardObservation(for: .text(result.output))
        pasteService.setClipboard(result.output)
        hudMessageController.show(message: L10n.text("hud.transformed"))
    }

    private func copyAndPaste(_ text: String, targetApplication: NSRunningApplication?) {
        suppressNextClipboardObservation(for: .text(text))
        pasteService.copyAndPaste(text, targetApplication: targetApplication)
    }

    private func copyOnly(_ text: String) {
        suppressNextClipboardObservation(for: .text(text))
        pasteService.setClipboard(text)
        hudMessageController.show(message: L10n.text("hud.copied"))
    }

    private func copyAndPaste(_ entry: HistoryEntry, targetApplication: NSRunningApplication?) {
        suppressNextClipboardObservation(for: entry.payload.primarySignature)
        guard pasteService.copyAndPaste(entry, targetApplication: targetApplication) else {
            return
        }
    }

    private func copyOnly(_ entry: HistoryEntry) {
        suppressNextClipboardObservation(for: entry.payload.primarySignature)
        guard pasteService.setClipboard(entry) else {
            return
        }
        hudMessageController.show(message: L10n.text("hud.copied"))
    }

    private func suppressNextClipboardObservation(for signature: ClipboardContentSignature) {
        clipboardMonitor.ignoreNextChange(matching: signature)
    }

    private func revealInFinder(_ entry: HistoryEntry) {
        // 履歴項目の Command+クリックは、元データではなく
        // Clipmo が管理している履歴ファイル自体を Finder で辿れる方が扱いやすいです。
        revealInFinder(existingFileURLs(from: [entry.fileURL.path]))
    }

    private func revealInFinder(_ content: SnippetContent) {
        revealInFinder(existingFileURLs(from: [content.sourceFileURL.path]))
    }

    private func revealInFinder(_ urls: [URL]) {
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func existingFileURLs(from paths: [String]) -> [URL] {
        paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
