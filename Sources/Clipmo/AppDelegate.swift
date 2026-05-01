// 起動時の配線と、設定変更時の再配線だけを担当する app のエントリポイントです。
// 各機能の本体は専用クラスへ寄せ、ここでは依存関係をつなぐことを主眼にしています。
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let paths = AppPaths()
    private lazy var configStore = ConfigStore(paths: paths)
    private lazy var deviceIdentityStore = DeviceIdentityStore(fileURL: paths.deviceIdentifierFile)
    private lazy var historyStore = ClipboardHistoryStore(directoryURL: paths.defaultHistoryDirectory)
    private lazy var snippetLoader = SnippetLoader(rootDirectory: paths.defaultSnippetsDirectory)
    private let snippetRenderer = SnippetRenderer()
    private lazy var transformStore = TransformStore(
        customDirectoryURL: paths.defaultTransformsDirectory
    )

    private let hotKeyManager = HotKeyManager()
    private let clipboardMonitor = ClipboardMonitor()
    private let pasteService = PasteService()
    private let hudMessageController = HUDMessageController()
    private lazy var configDirectoryMonitor = ConfigDirectoryMonitor(directoryURL: paths.baseDirectory)
    private lazy var clipboardWorkflow = ClipboardWorkflowController(
        historyStore: historyStore,
        snippetRenderer: snippetRenderer,
        transformStore: transformStore,
        clipboardMonitor: clipboardMonitor,
        pasteService: pasteService,
        hudMessageController: hudMessageController
    )

    private var menuBarController: MenuBarController?
    private var currentConfig = AppConfig.default
    private var targetApplication: NSRunningApplication?
    private var lastExternalApplication: NSRunningApplication?

    /// 起動時は config を読み、保存先と監視と menu をまとめて初期化します。
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 起動時に必要なファイル群を揃え、履歴件数だけ現在設定へ合わせます。
        currentConfig = configStore.loadInitialConfig()
        historyStore.updateDeviceIdentifier(deviceIdentityStore.loadOrCreate())
        applyStorageDirectories(from: currentConfig)
        historyStore.updateRetentionPolicy(currentConfig.historyRetention)
        historyStore.enforceLimit(currentConfig.maxHistoryCount)
        clipboardMonitor.ocrLanguages = currentConfig.ocrLanguages
        updateLastExternalApplication(with: NSWorkspace.shared.frontmostApplication)

        installApplicationObservers()
        menuBarController = configureMenuBarController()
        registerHotKey(using: currentConfig.hotKey, allowFallback: true)
        startMonitoring()

        AccessibilityPermissions.promptIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stop()
        configDirectoryMonitor.stop()
        hotKeyManager.unregister()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// MenuBarController は UI イベントを受けるだけにして、
    /// 実際の clipboard 操作は workflow 側へ流します。
    private func configureMenuBarController() -> MenuBarController {
        let controller = MenuBarController(
            historyStore: historyStore,
            snippetLoader: snippetLoader,
            snippetRenderer: snippetRenderer,
            transformStore: transformStore
        )
        controller.hotKeyConfiguration = currentConfig.hotKey
        controller.itemSelectionModifiers = currentConfig.itemSelectionModifiers
        controller.hotKeyMenuRotationNames = currentConfig.hotKeyMenuRotation
        controller.historyPreviewMaxWidth = CGFloat(currentConfig.menuPreviewMaxWidth)
        controller.historyItemsPerMenuLevel = currentConfig.historyItemsPerMenuLevel
        controller.willPresentMenu = { [weak self] in
            self?.capturePasteTargetApplication()
        }
        controller.onHistoryChosen = { [weak self] entry, mode in
            guard let self else {
                return
            }

            self.clipboardWorkflow.handleHistorySelection(
                entry,
                mode: mode,
                maxHistoryCount: self.currentConfig.maxHistoryCount,
                targetApplication: self.consumeTargetApplication()
            )
        }
        controller.onSnippetChosen = { [weak self] content, mode in
            guard let self else {
                return
            }

            self.clipboardWorkflow.handleSnippetSelection(
                content,
                mode: mode,
                maxHistoryCount: self.currentConfig.maxHistoryCount,
                targetApplication: self.consumeTargetApplication()
            )
        }
        controller.onApplyBuiltInTransform = { [weak self] identifier in
            guard let self else {
                return
            }

            self.clipboardWorkflow.applyBuiltInTransformToClipboard(
                identifier: identifier,
                maxHistoryCount: self.currentConfig.maxHistoryCount
            )
        }
        controller.onApplyCustomTransform = { [weak self] identifier in
            guard let self else {
                return
            }

            self.clipboardWorkflow.applyCustomTransformToClipboard(
                identifier: identifier,
                maxHistoryCount: self.currentConfig.maxHistoryCount
            )
        }
        controller.onOpenBaseDirectory = { [weak self] in
            self?.openBaseDirectoryInFinder()
        }
        controller.onQuit = {
            NSApp.terminate(nil)
        }
        return controller
    }

    private func installApplicationObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    private func startMonitoring() {
        configDirectoryMonitor.onChange = { [weak self] in
            self?.handleConfigDirectoryChange()
        }

        // clipboard の生イベントはここだけで受けて、
        // 履歴追加や手動変換後の書き戻し抑制を workflow 側へ集約します。
        clipboardMonitor.onObservation = { [weak self] observation in
            guard let self else {
                return
            }

            self.clipboardWorkflow.handleObservedClipboardContent(
                observation,
                maxHistoryCount: self.currentConfig.maxHistoryCount
            )
        }
        configDirectoryMonitor.start()
        clipboardMonitor.start()
    }

    private func handleConfigDirectoryChange() {
        guard let updatedConfig = configStore.reloadIfNeeded() else {
            return
        }

        applyConfig(updatedConfig)
    }

    /// config 再読込では、保存先・監視・menu 表示条件を一括で差し替えます。
    private func applyConfig(_ config: AppConfig) {
        currentConfig = config
        applyStorageDirectories(from: config)
        historyStore.updateRetentionPolicy(config.historyRetention)
        historyStore.enforceLimit(config.maxHistoryCount)
        clipboardMonitor.ocrLanguages = config.ocrLanguages
        menuBarController?.hotKeyConfiguration = config.hotKey
        menuBarController?.itemSelectionModifiers = config.itemSelectionModifiers
        menuBarController?.hotKeyMenuRotationNames = config.hotKeyMenuRotation
        menuBarController?.historyPreviewMaxWidth = CGFloat(config.menuPreviewMaxWidth)
        menuBarController?.historyItemsPerMenuLevel = config.historyItemsPerMenuLevel
        registerHotKey(using: config.hotKey, allowFallback: true)
    }

    private func applyStorageDirectories(from config: AppConfig) {
        let storageDirectories = paths.storageDirectories(for: config)

        do {
            try paths.prepareStorageDirectories(storageDirectories)
        } catch {
            print("Clipmo: ストレージディレクトリの作成に失敗しました: \(error)")
        }

        historyStore.updateDirectoryURL(storageDirectories.historyDirectory)
        snippetLoader.updateRootDirectory(storageDirectories.snippetsDirectory)
        transformStore.updateCustomDirectoryURL(storageDirectories.transformsDirectory)
    }

    private func registerHotKey(using configuration: HotKeyConfiguration, allowFallback: Bool) {
        do {
            try hotKeyManager.register(configuration: configuration) { [weak self] in
                self?.menuBarController?.showHotKeyMenu()
            }
        } catch {
            print("Clipmo: \(error.localizedDescription)")

            guard allowFallback, configuration != .default else {
                return
            }

            // 壊れた設定で完全に操作不能になるよりは、既定のホットキーへ戻して起動を優先します。
            registerHotKey(using: .default, allowFallback: false)
        }
    }

    private func capturePasteTargetApplication() {
        // ホットキーで menu を出した瞬間に Clipmo 自身が前面化しても、
        // 直前まで触っていたアプリへ貼り戻せるよう最後の外部 app を保持します。
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier {
            targetApplication = lastExternalApplication
            return
        }

        targetApplication = frontmostApplication
        updateLastExternalApplication(with: frontmostApplication)
    }

    private func openBaseDirectoryInFinder() {
        guard NSWorkspace.shared.open(paths.baseDirectory) else {
            NSSound.beep()
            return
        }
    }

    @objc private func handleApplicationDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        updateLastExternalApplication(with: application)
    }

    private func updateLastExternalApplication(with application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return
        }

        lastExternalApplication = application
    }

    private func consumeTargetApplication() -> NSRunningApplication? {
        let application = targetApplication
        targetApplication = nil
        return application
    }
}
