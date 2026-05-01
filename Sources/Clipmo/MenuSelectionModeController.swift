// メニュー表示中の modifier 解釈だけを担当します。
// `MenuBarController` から「いま paste/copy/reveal/repeat のどれか」を決める責務を外して、
// 表示制御と状態判定を分離するための小さな state machine です。
import AppKit

struct MenuSelectionModeController {
    private(set) var currentMode: ClipboardItemSelectionMode = .paste
    private var isArmed = true

    mutating func prepareForPresentation(
        _ presentation: MenuPresentation,
        itemSelectionModifiers: ItemSelectionModifierConfiguration,
        hotKeyConfiguration: HotKeyConfiguration
    ) {
        isArmed = shouldArmImmediately(
            for: presentation,
            itemSelectionModifiers: itemSelectionModifiers,
            hotKeyConfiguration: hotKeyConfiguration
        )
        currentMode = isArmed ? currentModeFromSystem(itemSelectionModifiers: itemSelectionModifiers) : .paste
    }

    mutating func finishPresentation() {
        currentMode = .paste
        isArmed = true
    }

    mutating func syncWithSystem(
        itemSelectionModifiers: ItemSelectionModifierConfiguration,
        hotKeyConfiguration: HotKeyConfiguration
    ) -> ClipboardItemSelectionMode? {
        if !isArmed,
           selectionActionFlagsOverlappingHotKeyFromSystem(
               itemSelectionModifiers: itemSelectionModifiers,
               hotKeyConfiguration: hotKeyConfiguration
           ).isEmpty {
            isArmed = true
        }

        let updatedMode = isArmed ? currentModeFromSystem(itemSelectionModifiers: itemSelectionModifiers) : .paste
        guard updatedMode != currentMode else {
            return nil
        }

        currentMode = updatedMode
        return updatedMode
    }

    func shouldReopenCurrentSelection() -> Bool {
        currentMode == .repeatSelection
    }

    private func shouldArmImmediately(
        for presentation: MenuPresentation,
        itemSelectionModifiers: ItemSelectionModifierConfiguration,
        hotKeyConfiguration: HotKeyConfiguration
    ) -> Bool {
        guard case .hotKey = presentation else {
            return true
        }

        // ホットキー自体に含まれていた modifier と重なるものだけを待てば十分です。
        // それ以外まで待つと、再表示直後の repeat mode が押しっぱなしで効かなくなります。
        return selectionActionFlagsOverlappingHotKeyFromSystem(
            itemSelectionModifiers: itemSelectionModifiers,
            hotKeyConfiguration: hotKeyConfiguration
        ).isEmpty
    }

    private func currentModeFromSystem(itemSelectionModifiers: ItemSelectionModifierConfiguration) -> ClipboardItemSelectionMode {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        if flags.contains(itemSelectionModifiers.revealInFinder.cgEventFlag) {
            return .revealInFinder
        }

        if flags.contains(itemSelectionModifiers.copyOnly.cgEventFlag) {
            return .copyOnly
        }

        if flags.contains(itemSelectionModifiers.repeatSelection.cgEventFlag) {
            return .repeatSelection
        }

        return .paste
    }

    private func selectionActionFlagsFromSystem(itemSelectionModifiers: ItemSelectionModifierConfiguration) -> CGEventFlags {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.intersection([
            itemSelectionModifiers.copyOnly.cgEventFlag,
            itemSelectionModifiers.revealInFinder.cgEventFlag,
            itemSelectionModifiers.repeatSelection.cgEventFlag
        ])
    }

    private func selectionActionFlagsOverlappingHotKeyFromSystem(
        itemSelectionModifiers: ItemSelectionModifierConfiguration,
        hotKeyConfiguration: HotKeyConfiguration
    ) -> CGEventFlags {
        selectionActionFlagsFromSystem(itemSelectionModifiers: itemSelectionModifiers)
            .intersection(hotKeyConfiguration.cgEventFlags)
    }
}
