// 履歴・スニペット・変換 menu の「構造」を組み立てるための builder です。
// 文字列整形やツールチップ生成は別 helper へ寄せて、ここでは section の配置順だけを扱います。
import AppKit

struct HistoryMenuSelection {
    let entry: HistoryEntry
    let accessKeyLabel: String
}

struct SnippetMenuSelection {
    let content: SnippetContent
}

private enum SectionHeaderKind: String {
    case history
    case snippet
    case transform
}

private enum TransformSectionMode {
    case all
    case builtInOnly
    case customOnly
}

@MainActor
final class MenuContentBuilder {
    struct Configuration {
        let scope: HotKeyMenuScope
        let historyPreviewMaxWidth: CGFloat
        let historyItemsPerMenuLevel: Int
        let includeStatusActions: Bool
    }

    struct ActionHandlers {
        let target: AnyObject
        let historySelection: Selector
        let snippetSelection: Selector
        let builtInTransformSelection: Selector
        let customTransformSelection: Selector
        let openBaseDirectory: Selector
        let quit: Selector
    }

    private let historyStore: ClipboardHistoryStore
    private let snippetLoader: SnippetLoader
    private let transformStore: TransformStore
    private let formatter: MenuContentFormatting
    private let accessKeyLabels = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)

    init(
        historyStore: ClipboardHistoryStore,
        snippetLoader: SnippetLoader,
        snippetRenderer: SnippetRenderer,
        transformStore: TransformStore
    ) {
        self.historyStore = historyStore
        self.snippetLoader = snippetLoader
        self.transformStore = transformStore
        self.formatter = MenuContentFormatting(snippetRenderer: snippetRenderer)
    }

    /// 現在の scope に応じて section を組み替えます。
    /// status item 用と hotkey 用で下部の操作群だけ差し替える前提です。
    func rebuild(_ menu: NSMenu, configuration: Configuration, actions: ActionHandlers) {
        menu.removeAllItems()
        addClipboardPreviewSectionIfNeeded(
            to: menu,
            configuration: configuration,
            alwaysShow: shouldAlwaysShowClipboardPreview(for: configuration.scope)
        )

        switch configuration.scope {
        case .all:
            addHistorySection(to: menu, configuration: configuration, actions: actions)
            menu.addItem(.separator())
            addSnippetSection(to: menu, actions: actions)
            menu.addItem(.separator())
            addTransformSection(to: menu, mode: .all, actions: actions)

        case .history:
            addHistorySection(to: menu, configuration: configuration, actions: actions)

        case .snippets:
            addSnippetSection(to: menu, actions: actions)

        case .snippet(let index):
            addSingleSnippetFolderSection(to: menu, folderIndex: index, actions: actions)

        case .transforms:
            addTransformSection(to: menu, mode: .all, actions: actions)

        case .builtInTransforms:
            addTransformSection(to: menu, mode: .builtInOnly, actions: actions)

        case .customTransforms:
            addTransformSection(to: menu, mode: .customOnly, actions: actions)
        }

        guard configuration.includeStatusActions else {
            return
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(title: L10n.text("menu.status.openClipmoFolder"), action: actions.openBaseDirectory, target: actions.target))
        menu.addItem(actionItem(title: L10n.text("menu.status.quitClipmo"), action: actions.quit, target: actions.target))
    }

    /// 変換 menu では常時、その他では「履歴先頭とズレているときだけ」
    /// 現在の clipboard を見せて、外部同期時の認知負荷を減らします。
    private func addClipboardPreviewSectionIfNeeded(to menu: NSMenu, configuration: Configuration, alwaysShow: Bool) {
        guard alwaysShow || shouldShowClipboardPreviewComparedToLatestHistory() else {
            return
        }

        menu.addItem(disabledSectionHeader(title: L10n.text("menu.section.currentClipboard")))

        guard let preview = currentClipboardPreview() else {
            if alwaysShow {
                menu.addItem(disabledItem(title: L10n.text("menu.section.currentClipboard.empty")))
                menu.addItem(.separator())
            }
            return
        }

        let item = disabledItem(
            title: formatter.previewText(
                for: preview.sourceText,
                accessKeyLabel: "",
                historyPreviewMaxWidth: configuration.historyPreviewMaxWidth
            )
        )
        item.toolTip = preview.toolTip
        menu.addItem(item)
        menu.addItem(.separator())
    }

    private func shouldAlwaysShowClipboardPreview(for scope: HotKeyMenuScope) -> Bool {
        switch scope {
        case .transforms, .builtInTransforms, .customTransforms:
            return true
        case .all, .history, .snippets, .snippet:
            return false
        }
    }

    private func shouldShowClipboardPreviewComparedToLatestHistory() -> Bool {
        guard let currentPreview = currentClipboardPreview(),
              let currentSignature = currentPreview.signature else {
            return false
        }

        guard let latestEntry = historyStore.entries().first else {
            return true
        }

        return latestEntry.payload.primarySignature != currentSignature
    }

    private func currentClipboardPreview() -> CurrentClipboardPreview? {
        CurrentClipboardPreviewProvider.load(formatter: formatter)
    }

    /// modifier に応じた見出しだけは menu tracking 中に差し替えます。
    func updateSectionHeaders(in menu: NSMenu, selectionMode: ClipboardItemSelectionMode) {
        for item in menu.items {
            guard
                let rawValue = item.representedObject as? String,
                let kind = SectionHeaderKind(rawValue: rawValue)
            else {
                continue
            }

            item.title = sectionHeaderTitle(for: kind, selectionMode: selectionMode)
        }
    }

    private func addHistorySection(to menu: NSMenu, configuration: Configuration, actions: ActionHandlers) {
        menu.addItem(sectionHeaderItem(kind: .history, selectionMode: .paste))
        addHistoryItems(to: menu, configuration: configuration, actions: actions)
    }

    /// 履歴は top level を浅く保つため、古い側は sibling submenu として並べます。
    private func addHistoryItems(to menu: NSMenu, configuration: Configuration, actions: ActionHandlers) {
        let entries = historyStore.entries()
        let itemsInThisLevel = max(1, configuration.historyItemsPerMenuLevel)

        guard !entries.isEmpty else {
            menu.addItem(disabledItem(title: L10n.text("menu.history.empty")))
            return
        }

        for (index, entry) in entries.prefix(itemsInThisLevel).enumerated() {
            let accessKeyLabel = accessKeyLabel(for: index)
            menu.addItem(historyMenuItem(for: entry, accessKeyLabel: accessKeyLabel, configuration: configuration, actions: actions))
        }

        var startIndex = itemsInThisLevel
        while startIndex < entries.count {
            let endIndex = min(startIndex + itemsInThisLevel, entries.count)
            let submenuTitle = historyOverflowMenuTitle(start: startIndex + 1, end: endIndex)
            let submenu = submenu(title: submenuTitle, target: actions.target)

            for (submenuIndex, entry) in entries[startIndex..<endIndex].enumerated() {
                let accessKeyLabel = accessKeyLabel(for: submenuIndex)
                submenu.addItem(historyMenuItem(for: entry, accessKeyLabel: accessKeyLabel, configuration: configuration, actions: actions))
            }

            let item = NSMenuItem(title: submenuTitle, action: nil, keyEquivalent: "")
            item.attributedTitle = formatter.attributedFolderTitle(for: submenuTitle)
            item.submenu = submenu
            menu.addItem(item)
            startIndex = endIndex
        }
    }

    private func addSnippetSection(to menu: NSMenu, actions: ActionHandlers) {
        menu.addItem(sectionHeaderItem(kind: .snippet, selectionMode: .paste))
        addSnippetItems(to: menu, actions: actions)
    }

    private func addSnippetItems(to menu: NSMenu, actions: ActionHandlers) {
        let snippets = snippetLoader.load()
        guard !snippets.isEmpty else {
            menu.addItem(disabledItem(title: L10n.text("menu.snippets.empty")))
            return
        }

        populateSnippetNodes(snippets, into: menu, actions: actions)
    }

    /// `snippet0` のような hotkey 専用 scope では、そのフォルダの子だけを root に展開します。
    private func addSingleSnippetFolderSection(to menu: NSMenu, folderIndex: Int, actions: ActionHandlers) {
        menu.addItem(sectionHeaderItem(kind: .snippet, selectionMode: .paste))

        let topLevelFolders = snippetLoader.load().compactMap { node -> [SnippetNode]? in
            guard case .folder(_, let children) = node else {
                return nil
            }

            return children
        }

        guard topLevelFolders.indices.contains(folderIndex) else {
            menu.addItem(disabledItem(title: L10n.text("menu.snippets.empty")))
            return
        }

        let targetNodes = topLevelFolders[folderIndex]
        guard !targetNodes.isEmpty else {
            menu.addItem(disabledItem(title: L10n.text("menu.common.empty")))
            return
        }

        populateSnippetNodes(targetNodes, into: menu, actions: actions)
    }

    private func addTransformSection(to menu: NSMenu, mode: TransformSectionMode, actions: ActionHandlers) {
        menu.addItem(sectionHeaderItem(kind: .transform, selectionMode: .paste))
        addTransformItems(to: menu, mode: mode, actions: actions)
    }

    /// 変換は clipboard にテキストがあるときだけ意味があるので、ここで enabled をまとめて切り替えます。
    private func addTransformItems(to menu: NSMenu, mode: TransformSectionMode, actions: ActionHandlers) {
        let hasClipboardText = PasteboardTextResolver.preferredText(from: .general) != nil

        switch mode {
        case .all:
            let builtInMenu = submenu(title: L10n.text("menu.transforms.builtIn"), target: actions.target)
            populateBuiltInTransforms(into: builtInMenu, actions: actions, isEnabled: hasClipboardText)

            let customMenu = submenu(title: L10n.text("menu.transforms.custom"), target: actions.target)
            populateCustomTransforms(into: customMenu, actions: actions, isEnabled: hasClipboardText)

            let builtInItem = NSMenuItem(title: L10n.text("menu.transforms.builtIn"), action: nil, keyEquivalent: "")
            builtInItem.submenu = builtInMenu
            menu.addItem(builtInItem)

            let customItem = NSMenuItem(title: L10n.text("menu.transforms.custom"), action: nil, keyEquivalent: "")
            customItem.submenu = customMenu
            menu.addItem(customItem)

        case .builtInOnly:
            populateBuiltInTransforms(into: menu, actions: actions, isEnabled: hasClipboardText)

        case .customOnly:
            populateCustomTransforms(into: menu, actions: actions, isEnabled: hasClipboardText)
        }
    }

    private func populateBuiltInTransforms(into menu: NSMenu, actions: ActionHandlers, isEnabled: Bool) {
        for transform in transformStore.builtInTransforms() {
            let item = actionItem(
                title: transform.displayName,
                action: actions.builtInTransformSelection,
                target: actions.target
            )
            item.representedObject = transform.identifier
            item.toolTip = transform.toolTip
            item.isEnabled = isEnabled
            menu.addItem(item)
        }
    }

    private func populateCustomTransforms(into menu: NSMenu, actions: ActionHandlers, isEnabled: Bool) {
        let customTransforms = transformStore.customTransforms()
        guard !customTransforms.isEmpty else {
            menu.addItem(disabledItem(title: L10n.text("menu.transforms.custom.empty")))
            return
        }

        for transform in customTransforms {
            let item = actionItem(
                title: transform.displayName,
                action: actions.customTransformSelection,
                target: actions.target
            )
            item.representedObject = transform.identifier
            item.toolTip = formatter.customTransformTooltipText(for: transform)
            item.isEnabled = isEnabled
            menu.addItem(item)
        }
    }

    private func populateSnippetNodes(_ nodes: [SnippetNode], into menu: NSMenu, actions: ActionHandlers) {
        for node in nodes {
            switch node {
            case .item(let name, let content, _):
                let item = actionItem(title: name, action: actions.snippetSelection, target: actions.target)
                item.representedObject = SnippetMenuSelection(content: content)
                item.toolTip = formatter.snippetTooltipText(for: content)
                menu.addItem(item)

            case .folder(let name, let children):
                let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                item.attributedTitle = formatter.attributedFolderTitle(for: name)
                let submenu = submenu(title: name, target: actions.target)

                if children.isEmpty {
                    submenu.addItem(disabledItem(title: L10n.text("menu.common.empty")))
                } else {
                    populateSnippetNodes(children, into: submenu, actions: actions)
                }

                item.submenu = submenu
                menu.addItem(item)
            }
        }
    }

    private func historyMenuItem(
        for entry: HistoryEntry,
        accessKeyLabel: String,
        configuration: Configuration,
        actions: ActionHandlers
    ) -> NSMenuItem {
        let body = formatter.previewText(
            for: formatter.historyPreviewSourceText(for: entry.payload),
            accessKeyLabel: accessKeyLabel,
            historyPreviewMaxWidth: configuration.historyPreviewMaxWidth
        )
        let item = actionItem(
            title: "\(accessKeyLabel). \(body)",
            action: actions.historySelection,
            target: actions.target
        )
        item.representedObject = HistoryMenuSelection(entry: entry, accessKeyLabel: accessKeyLabel)
        item.toolTip = formatter.historyTooltipText(for: entry)
        return item
    }

    private func actionItem(title: String, action: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }

    private func sectionHeaderItem(kind: SectionHeaderKind, selectionMode: ClipboardItemSelectionMode) -> NSMenuItem {
        let item = NSMenuItem.sectionHeader(title: sectionHeaderTitle(for: kind, selectionMode: selectionMode))
        item.representedObject = kind.rawValue
        return item
    }

    private func sectionHeaderTitle(for kind: SectionHeaderKind, selectionMode: ClipboardItemSelectionMode) -> String {
        switch kind {
        case .history:
            switch selectionMode {
            case .paste:
                return L10n.text("menu.section.history")
            case .copyOnly:
                return L10n.text("menu.section.history.copyOnly")
            case .revealInFinder:
                return L10n.text("menu.section.history.revealInFinder")
            case .repeatSelection:
                return L10n.text("menu.section.history.repeatPaste")
            }
        case .snippet:
            switch selectionMode {
            case .paste:
                return L10n.text("menu.section.snippets")
            case .copyOnly:
                return L10n.text("menu.section.snippets.copyOnly")
            case .revealInFinder:
                return L10n.text("menu.section.snippets.revealInFinder")
            case .repeatSelection:
                return L10n.text("menu.section.snippets.repeatPaste")
            }
        case .transform:
            switch selectionMode {
            case .repeatSelection:
                return L10n.text("menu.section.transforms.repeatApply")
            case .paste, .copyOnly, .revealInFinder:
                return L10n.text("menu.section.transforms")
            }
        }
    }

    private func disabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func disabledSectionHeader(title: String) -> NSMenuItem {
        let item = NSMenuItem.sectionHeader(title: title)
        item.isEnabled = false
        return item
    }

    private func submenu(title: String, target: AnyObject) -> NSMenu {
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        submenu.delegate = target as? NSMenuDelegate
        return submenu
    }

    private func accessKeyLabel(for index: Int) -> String {
        guard index < accessKeyLabels.count else {
            return "*"
        }

        return accessKeyLabels[index]
    }

    private func historyOverflowMenuTitle(start: Int, end: Int) -> String {
        if start == end {
            return "\(start)"
        }

        return "\(start) - \(end)"
    }
}
