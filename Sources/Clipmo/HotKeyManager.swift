// Carbon の RegisterEventHotKey を薄く包んで、app 全体からは Swift の設定だけを見せます。
// 古い API 名ですが、単一グローバルホットキー用途では今でも実装が素直です。
import AppKit
import Carbon
import Foundation

enum HotKeyError: LocalizedError {
    case unsupportedKey(String)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedKey(let key):
            return L10n.format("error.hotKey.unsupportedKey", key)
        case .registrationFailed(let status):
            return L10n.format("error.hotKey.registrationFailed", status)
        }
    }
}

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var callback: (() -> Void)?

    init() {
        installHandlerIfNeeded()
    }

    deinit {
        unregister()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// ホットキーは登録し直しが前提なので、毎回いったん前の登録を外します。
    func register(configuration: HotKeyConfiguration, callback: @escaping () -> Void) throws {
        unregister()

        guard let keyCode = KeyCodeMap.code(for: configuration.key) else {
            throw HotKeyError.unsupportedKey(configuration.key)
        }

        self.callback = callback

        let hotKeyID = EventHotKeyID(signature: fourCharCode("CLMO"), id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            configuration.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            throw HotKeyError.registrationFailed(status)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    /// グローバルホットキーの通知は app target へまとめて流し、closure へ橋渡しします。
    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, _, userData in
            guard let userData else {
                return noErr
            }

            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.callback?()
            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        if status != noErr {
            print("Clipmo: ホットキーイベントの登録に失敗しました: \(status)")
        }
    }

    private func fourCharCode(_ string: String) -> OSType {
        string.unicodeScalars.reduce(0) { value, scalar in
            (value << 8) + OSType(scalar.value)
        }
    }
}

enum KeyCodeMap {
    private static let mapping: [String: UInt32] = [
        "a": UInt32(kVK_ANSI_A),
        "b": UInt32(kVK_ANSI_B),
        "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D),
        "e": UInt32(kVK_ANSI_E),
        "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G),
        "h": UInt32(kVK_ANSI_H),
        "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J),
        "k": UInt32(kVK_ANSI_K),
        "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M),
        "n": UInt32(kVK_ANSI_N),
        "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P),
        "q": UInt32(kVK_ANSI_Q),
        "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S),
        "t": UInt32(kVK_ANSI_T),
        "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V),
        "w": UInt32(kVK_ANSI_W),
        "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y),
        "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0),
        "1": UInt32(kVK_ANSI_1),
        "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3),
        "4": UInt32(kVK_ANSI_4),
        "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6),
        "7": UInt32(kVK_ANSI_7),
        "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
        "space": UInt32(kVK_Space),
        "return": UInt32(kVK_Return),
        "enter": UInt32(kVK_Return),
        "tab": UInt32(kVK_Tab),
        "escape": UInt32(kVK_Escape),
        "delete": UInt32(kVK_Delete),
        "forwarddelete": UInt32(kVK_ForwardDelete),
        "left": UInt32(kVK_LeftArrow),
        "right": UInt32(kVK_RightArrow),
        "up": UInt32(kVK_UpArrow),
        "down": UInt32(kVK_DownArrow),
        "f1": UInt32(kVK_F1),
        "f2": UInt32(kVK_F2),
        "f3": UInt32(kVK_F3),
        "f4": UInt32(kVK_F4),
        "f5": UInt32(kVK_F5),
        "f6": UInt32(kVK_F6),
        "f7": UInt32(kVK_F7),
        "f8": UInt32(kVK_F8),
        "f9": UInt32(kVK_F9),
        "f10": UInt32(kVK_F10),
        "f11": UInt32(kVK_F11),
        "f12": UInt32(kVK_F12)
    ]

    static func code(for key: String) -> UInt32? {
        mapping[key.lowercased()]
    }
}

private extension HotKeyConfiguration {
    var carbonModifiers: UInt32 {
        modifiers.reduce(0) { $0 | $1.carbonModifier }
    }
}

private extension ItemSelectionModifierKey {
    var carbonModifier: UInt32 {
        switch self {
        case .command:
            return UInt32(cmdKey)
        case .option:
            return UInt32(optionKey)
        case .control:
            return UInt32(controlKey)
        case .shift:
            return UInt32(shiftKey)
        }
    }
}

extension HotKeyConfiguration {
    var eventModifierFlags: NSEvent.ModifierFlags {
        modifiers.reduce(into: NSEvent.ModifierFlags()) { result, modifier in
            result.insert(modifier.hotKeyEventModifierFlag)
        }
    }

    var cgEventFlags: CGEventFlags {
        modifiers.reduce(into: CGEventFlags()) { result, modifier in
            result.insert(modifier.hotKeyCGEventFlag)
        }
    }
}

private extension ItemSelectionModifierKey {
    var hotKeyEventModifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .command:
            return .command
        case .option:
            return .option
        case .control:
            return .control
        case .shift:
            return .shift
        }
    }

    var hotKeyCGEventFlag: CGEventFlags {
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
