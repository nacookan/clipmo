// ホットキーで開くメニューの「何番目を出すか」と「どこに出すか」を管理します。
// `MenuBarController` 側では、表示・キャンセル・再表示のタイミングだけを扱える状態にします。
import AppKit
import Foundation

struct HotKeyMenuSequenceController {
    private var rotation: [HotKeyMenuScope] = [.all]
    private var currentRotationIndex = 0
    private var activeMenuOrigin: NSPoint?
    private var lastObservedHotKeyPressedState = false
    private var isRotationArmed = false
    private var queuedScope: HotKeyMenuScope?
    private var suppressedCallbacks = 0
    private var suppressCallbacksUntil: Date?

    mutating func updateRotation(configNames: [String]) {
        let resolvedRotation = configNames.compactMap(HotKeyMenuScope.init(configName:))
        rotation = resolvedRotation.isEmpty ? [.all] : resolvedRotation
        currentRotationIndex = 0
    }

    mutating func beginNewSequence() -> HotKeyMenuScope {
        currentRotationIndex = 0
        activeMenuOrigin = nil
        return rotation.first ?? .all
    }

    mutating func prepareForPresentation(isHotKeyPressed: Bool) {
        lastObservedHotKeyPressedState = isHotKeyPressed
        isRotationArmed = false
    }

    mutating func resolvedOrigin(fallback: NSPoint) -> NSPoint {
        let origin = activeMenuOrigin ?? fallback
        activeMenuOrigin = origin
        return origin
    }

    mutating func pollDuringMenuTracking(isHotKeyPressed: Bool) -> Bool {
        if !isRotationArmed {
            if !isHotKeyPressed {
                isRotationArmed = true
            }
            lastObservedHotKeyPressedState = isHotKeyPressed
            return false
        }

        guard isHotKeyPressed && !lastObservedHotKeyPressedState else {
            lastObservedHotKeyPressedState = isHotKeyPressed
            return false
        }

        lastObservedHotKeyPressedState = true
        queueNextScope()
        return true
    }

    mutating func nextQueuedScopeAfterMenuClose(
        hadPendingAction: Bool,
        presentation: MenuPresentation
    ) -> HotKeyMenuScope? {
        guard !hadPendingAction else {
            queuedScope = nil
            return nil
        }

        if let queuedScope {
            self.queuedScope = nil
            return queuedScope
        }

        if !hadPendingAction, case .hotKey = presentation {
            currentRotationIndex = 0
        }

        return nil
    }

    mutating func finishPresentation() {
        lastObservedHotKeyPressedState = false
        isRotationArmed = false
    }

    mutating func consumeSuppressedCallbackIfNeeded(now: Date = Date()) -> Bool {
        guard suppressedCallbacks > 0 else {
            return false
        }

        if let deadline = suppressCallbacksUntil, now > deadline {
            suppressedCallbacks = 0
            suppressCallbacksUntil = nil
            return false
        }

        suppressedCallbacks -= 1
        if suppressedCallbacks == 0 {
            suppressCallbacksUntil = nil
        }

        return true
    }

    private mutating func queueNextScope() {
        guard queuedScope == nil else {
            return
        }

        currentRotationIndex = (currentRotationIndex + 1) % rotation.count
        queuedScope = rotation[currentRotationIndex]
        suppressedCallbacks += 1
        suppressCallbacksUntil = Date().addingTimeInterval(0.5)
    }
}
