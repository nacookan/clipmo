// メニューバー icon とグローバルホットキーの両方から menu を表示し、
// 選択結果を app 本体へ返すための UI 制御レイヤです。
// 実際の clipboard 操作は持たず、表示タイミングと AppKit の癖への対処に集中します。
import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onHistoryChosen: ((HistoryEntry, ClipboardItemSelectionMode) -> Void)?
    var onSnippetChosen: ((SnippetContent, ClipboardItemSelectionMode) -> Void)?
    var onApplyBuiltInTransform: ((String) -> Void)?
    var onApplyCustomTransform: ((String) -> Void)?
    var onOpenBaseDirectory: (() -> Void)?
    var onQuit: (() -> Void)?
    var willPresentMenu: (() -> Void)?
    var hotKeyConfiguration: HotKeyConfiguration = .default
    var itemSelectionModifiers: ItemSelectionModifierConfiguration = .default
    var hotKeyMenuRotationNames: [String] = ["all"] {
        didSet {
            hotKeySequenceController.updateRotation(configNames: hotKeyMenuRotationNames)
        }
    }
    var historyPreviewMaxWidth: CGFloat = CGFloat(AppConfig.default.menuPreviewMaxWidth)
    var historyItemsPerMenuLevel: Int = AppConfig.default.historyItemsPerMenuLevel

    private let contentBuilder: MenuContentBuilder
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var selectionModeController = MenuSelectionModeController()
    private var hotKeySequenceController = HotKeyMenuSequenceController()
    private var presentation: MenuPresentation = .statusItem
    private var pendingAction: PendingAction?
    private var keyMonitor: Any?
    private var modifierStateTimer: Timer?
    private var openMenus: [NSMenu] = []

    private enum PendingAction {
        case historyEntry(HistoryEntry, ClipboardItemSelectionMode)
        case snippetText(SnippetContent, ClipboardItemSelectionMode)
        case applyBuiltInTransform(String, Bool)
        case applyCustomTransform(String, Bool)
        case openBaseDirectory
        case quit
    }

    init(
        historyStore: ClipboardHistoryStore,
        snippetLoader: SnippetLoader,
        snippetRenderer: SnippetRenderer,
        transformStore: TransformStore
    ) {
        contentBuilder = MenuContentBuilder(
            historyStore: historyStore,
            snippetLoader: snippetLoader,
            snippetRenderer: snippetRenderer,
            transformStore: transformStore
        )
        super.init()
        hotKeySequenceController.updateRotation(configNames: hotKeyMenuRotationNames)
        configureStatusItem()
    }

    /// グローバルホットキーからの起点です。通常の新規表示だけを受け付け、
    /// menu tracking 中の再押下は timer 側の polling で処理します。
    func showHotKeyMenu() {
        if hotKeySequenceController.consumeSuppressedCallbackIfNeeded() {
            return
        }

        guard openMenus.isEmpty else {
            return
        }

        handleHotKeyActivation(hotKeySequenceController.beginNewSequence())
    }

    /// ステータスアイテムは mouseDown で即開いて、体感の遅さを減らします。
    private func configureStatusItem() {
        menu.autoenablesItems = false
        menu.delegate = self

        guard let button = statusItem.button else {
            return
        }

        if let image = NSImage(systemSymbolName: "list.bullet.clipboard.fill", accessibilityDescription: "Clipmo") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "CB"
        }

        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    /// AppKit の menu tracking 中は key 状態や submenu 展開が特殊なので、
    /// 表示前に必要な監視を立て、閉じたあとに選択処理を遅延実行します。
    private func presentMenu(as presentation: MenuPresentation) {
        self.presentation = presentation
        pendingAction = nil
        selectionModeController.prepareForPresentation(
            presentation,
            itemSelectionModifiers: itemSelectionModifiers,
            hotKeyConfiguration: hotKeyConfiguration
        )
        hotKeySequenceController.prepareForPresentation(isHotKeyPressed: currentConfiguredHotKeyPressedState())
        openMenus.removeAll()
        installKeyMonitor()
        startModifierStateTimer()
        willPresentMenu?()
        rebuildMenu()

        switch presentation {
        case .statusItem:
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        case .hotKey:
            let origin = hotKeySequenceController.resolvedOrigin(fallback: hotKeyMenuOrigin())
            menu.popUp(positioning: nil, at: origin, in: nil)
        }

        removeKeyMonitor()
        stopModifierStateTimer()
        openMenus.removeAll()
        selectionModeController.finishPresentation()
        hotKeySequenceController.finishPresentation()

        // 選択アクション本体は menu tracking が完全に終わってから実行します。
        // ここで早すぎると貼り付け先アプリへキー送信するタイミングが不安定になります。
        performPendingActionIfNeeded()
    }

    /// 表示構造の組み立ては builder に任せ、controller 側は現在の mode だけ渡します。
    private func rebuildMenu() {
        contentBuilder.rebuild(
            menu,
            configuration: .init(
                scope: activeMenuScope(),
                historyPreviewMaxWidth: historyPreviewMaxWidth,
                historyItemsPerMenuLevel: historyItemsPerMenuLevel,
                includeStatusActions: isStatusItemPresentation()
            ),
            actions: .init(
                target: self,
                historySelection: #selector(handleHistorySelection(_:)),
                snippetSelection: #selector(handleSnippetSelection(_:)),
                builtInTransformSelection: #selector(handleBuiltInTransformSelection(_:)),
                customTransformSelection: #selector(handleCustomTransformSelection(_:)),
                openBaseDirectory: #selector(handleOpenBaseDirectory(_:)),
                quit: #selector(handleQuit(_:))
            )
        )
        contentBuilder.updateSectionHeaders(in: menu, selectionMode: selectionModeController.currentMode)
    }

    /// 「全部入り」なのか hotkey 用の限定 scope なのかを menu builder に伝えます。
    private func activeMenuScope() -> HotKeyMenuScope {
        switch presentation {
        case .statusItem:
            return .all
        case .hotKey(let scope):
            return scope
        }
    }

    private func isStatusItemPresentation() -> Bool {
        if case .statusItem = presentation {
            return true
        }

        return false
    }

    /// hotkey menu はカーソル位置を起点にしますが、下にはみ出すと scroll menu になって使いにくいので、
    /// まず「できるだけ入り切る原点」へ補正してから出します。
    private func hotKeyMenuOrigin() -> NSPoint {
        let mouseLocation = NSEvent.mouseLocation
        let menuSize = menu.size
        guard let visibleFrame = screenForMenu(at: mouseLocation)?.visibleFrame else {
            return mouseLocation
        }

        let minX = visibleFrame.minX
        let maxX = max(minX, visibleFrame.maxX - menuSize.width)
        let minY = min(visibleFrame.maxY, visibleFrame.minY + menuSize.height)
        let maxY = visibleFrame.maxY

        return NSPoint(
            x: min(max(mouseLocation.x, minX), maxX),
            y: min(max(mouseLocation.y, minY), maxY)
        )
    }

    private func screenForMenu(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.visibleFrame.contains(point) })
            ?? NSScreen.screens.first(where: { $0.frame.contains(point) })
            ?? NSScreen.main
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        presentMenu(as: .statusItem)
    }

    @objc private func handleHistorySelection(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? HistoryMenuSelection else {
            return
        }

        pendingAction = .historyEntry(selection.entry, selectionModeController.currentMode)
    }

    @objc private func handleSnippetSelection(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? SnippetMenuSelection else {
            return
        }

        pendingAction = .snippetText(selection.content, selectionModeController.currentMode)
    }

    @objc private func handleOpenBaseDirectory(_ sender: Any?) {
        pendingAction = .openBaseDirectory
    }

    @objc private func handleBuiltInTransformSelection(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else {
            return
        }

        pendingAction = .applyBuiltInTransform(identifier, selectionModeController.shouldReopenCurrentSelection())
    }

    @objc private func handleCustomTransformSelection(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else {
            return
        }

        pendingAction = .applyCustomTransform(identifier, selectionModeController.shouldReopenCurrentSelection())
    }

    @objc private func handleQuit(_ sender: Any?) {
        pendingAction = .quit
    }

    /// menu を閉じた直後に、選択結果を callback として外へ渡します。
    /// hotkey ローテーションで次の menu を出すケースと、repeat mode の再表示もここで整理します。
    private func performPendingActionIfNeeded() {
        guard let pendingAction else {
            if let queuedScope = hotKeySequenceController.nextQueuedScopeAfterMenuClose(
                hadPendingAction: false,
                presentation: presentation
            ) {
                DispatchQueue.main.async {
                    self.presentMenu(as: .hotKey(queuedScope))
                }
            }
            return
        }

        self.pendingAction = nil
        _ = hotKeySequenceController.nextQueuedScopeAfterMenuClose(
            hadPendingAction: true,
            presentation: presentation
        )

        let reopenPresentation = followUpPresentation(after: pendingAction)
        let reopenDelay = reopenDelay(after: pendingAction)

        DispatchQueue.main.async {
            switch pendingAction {
            case .historyEntry(let entry, let mode):
                self.onHistoryChosen?(entry, mode)
            case .snippetText(let text, let mode):
                self.onSnippetChosen?(text, mode)
            case .applyBuiltInTransform(let identifier, _):
                self.onApplyBuiltInTransform?(identifier)
            case .applyCustomTransform(let identifier, _):
                self.onApplyCustomTransform?(identifier)
            case .openBaseDirectory:
                self.onOpenBaseDirectory?()
            case .quit:
                self.onQuit?()
            }

            guard let reopenPresentation else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + reopenDelay) {
                self.presentMenu(as: reopenPresentation)
            }
        }
    }

    /// submenu を開いた状態でも、常に「いま前面に見えている menu」に対して
    /// アクセスキーを解決したいので local monitor で拾っています。
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handleMenuKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else {
            return
        }

        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func handleMenuKeyEvent(_ event: NSEvent) -> NSEvent? {
        let disallowedModifiers = event.modifierFlags.intersection([.command, .control, .option, .function])
        guard disallowedModifiers.isEmpty else {
            return event
        }

        guard let character = event.charactersIgnoringModifiers?.uppercased(), character.count == 1 else {
            return event
        }

        let currentMenu = openMenus.last ?? menu
        guard let itemIndex = currentMenu.items.firstIndex(where: {
            guard
                $0.isEnabled,
                let selection = $0.representedObject as? HistoryMenuSelection
            else {
                return false
            }

            return selection.accessKeyLabel == character
        }) else {
            return event
        }

        currentMenu.performActionForItem(at: itemIndex)
        return nil
    }

    private func followUpPresentation(after pendingAction: PendingAction) -> MenuPresentation? {
        switch pendingAction {
        case .historyEntry(_, .repeatSelection), .snippetText(_, .repeatSelection):
            return presentation
        case .applyBuiltInTransform(_, let shouldReopen), .applyCustomTransform(_, let shouldReopen):
            return shouldReopen ? presentation : nil
        case .historyEntry(_, _), .snippetText(_, _), .openBaseDirectory, .quit:
            return nil
        }
    }

    private func reopenDelay(after pendingAction: PendingAction) -> TimeInterval {
        switch pendingAction {
        case .historyEntry(_, .repeatSelection), .snippetText(_, .repeatSelection):
            // 貼り付けは menu close 後に非同期で前面復帰と Command+V を送るので、
            // 再表示はその送信が終わる側へ少し逃がして干渉を減らします。
            return 0.18
        case .applyBuiltInTransform(_, let shouldReopen), .applyCustomTransform(_, let shouldReopen):
            return shouldReopen ? 0.05 : 0
        case .historyEntry(_, _), .snippetText(_, _), .openBaseDirectory, .quit:
            return 0
        }
    }

    private func handleHotKeyActivation(_ scope: HotKeyMenuScope) {
        guard openMenus.isEmpty else {
            return
        }

        presentMenu(as: .hotKey(scope))
    }

    /// AppKit の menu tracking 中は flagsChanged が安定しないことがあるので、
    /// hotkey の押し直し検知と section header の mode 表示だけは短い polling で見ます。
    private func startModifierStateTimer() {
        stopModifierStateTimer()

        let timer = Timer(timeInterval: 0.05, target: self, selector: #selector(handleModifierStateTimer), userInfo: nil, repeats: true)
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        self.modifierStateTimer = timer
    }

    private func stopModifierStateTimer() {
        modifierStateTimer?.invalidate()
        modifierStateTimer = nil
    }

    @objc private func handleModifierStateTimer() {
        let isHotKeyPressed = currentConfiguredHotKeyPressedState()

        if hotKeySequenceController.pollDuringMenuTracking(isHotKeyPressed: isHotKeyPressed) {
            menu.cancelTrackingWithoutAnimation()
            return
        }

        guard let selectionMode = selectionModeController.syncWithSystem(
            itemSelectionModifiers: itemSelectionModifiers,
            hotKeyConfiguration: hotKeyConfiguration
        ) else {
            return
        }

        contentBuilder.updateSectionHeaders(in: menu, selectionMode: selectionMode)
    }

    private func currentConfiguredHotKeyPressedState() -> Bool {
        guard let keyCode = KeyCodeMap.code(for: hotKeyConfiguration.key) else {
            return false
        }

        let flags = CGEventSource.flagsState(.combinedSessionState)
        let relevantFlags = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
            && relevantFlags == hotKeyConfiguration.cgEventFlags
    }

    func menuWillOpen(_ menu: NSMenu) {
        openMenus.removeAll { $0 === menu }
        openMenus.append(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        openMenus.removeAll { $0 === menu }
    }
}
