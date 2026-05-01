// 変換や OCR の結果を短く画面中央付近へ出す、軽量な HUD 表示です。
// 通知センターでは重すぎるので、非アクティブ panel を自前で扱います。
import AppKit

@MainActor
final class HUDMessageController {
    private let panel: NSPanel
    private let contentView = NSView()
    private let messageLabel = NSTextField(labelWithString: "")
    private let messageFont = NSFont.systemFont(ofSize: 18, weight: .medium)
    private var hideWorkItem: DispatchWorkItem?
    private let horizontalPadding: CGFloat = 28
    private let verticalPadding: CGFloat = 18
    private let panelWidth: CGFloat = 420

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        configureContent()
    }

    /// メッセージ長に合わせて panel サイズを測り直し、表示後は自動で消します。
    func show(message: String) {
        hideWorkItem?.cancel()

        messageLabel.stringValue = message
        let textRect = measuredTextRect(for: message)
        let panelSize = measuredPanelSize(for: textRect)
        panel.setContentSize(panelSize)
        contentView.frame = NSRect(origin: .zero, size: panelSize)
        layoutMessageLabel(in: contentView.bounds, textHeight: ceil(textRect.height))
        panel.setFrameOrigin(panelOrigin(for: panelSize))

        if panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }

        let hideWorkItem = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        self.hideWorkItem = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: hideWorkItem)
    }

    private func hide() {
        guard panel.isVisible else {
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        })
    }

    /// 非アクティブなまま前面へ出すために、borderless / nonactivatingPanel を使います。
    private func configurePanel() {
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
    }

    /// 標準 HUD そのものの公開 API はないので、必要な見た目だけを最小構成で再現します。
    private func configureContent() {
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        contentView.layer?.cornerRadius = 18
        contentView.layer?.masksToBounds = true

        messageLabel.font = messageFont
        messageLabel.alignment = .center
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.textColor = .white
        messageLabel.translatesAutoresizingMaskIntoConstraints = true
        messageLabel.cell?.wraps = true
        messageLabel.cell?.isScrollable = false
        messageLabel.cell?.usesSingleLineMode = false
        messageLabel.cell?.truncatesLastVisibleLine = false

        contentView.addSubview(messageLabel)
        panel.contentView = contentView
    }

    private func measuredTextRect(for message: String) -> NSRect {
        let attributes: [NSAttributedString.Key: Any] = [.font: messageFont]
        return (message as NSString).boundingRect(
            with: NSSize(width: panelWidth - (horizontalPadding * 2), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }

    private func measuredPanelSize(for textRect: NSRect) -> NSSize {
        let height = max(68, ceil(textRect.height) + (verticalPadding * 2))
        return NSSize(width: panelWidth, height: height)
    }

    private func layoutMessageLabel(in bounds: NSRect, textHeight: CGFloat) {
        let labelWidth = bounds.width - (horizontalPadding * 2)
        let labelHeight = max(ceil(textHeight), 22)
        let originY = round((bounds.height - labelHeight) / 2)

        messageLabel.frame = NSRect(
            x: horizontalPadding,
            y: originY,
            width: labelWidth,
            height: labelHeight
        )
    }

    private func panelOrigin(for panelSize: NSSize) -> NSPoint {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = screen(for: mouseLocation) else {
            return NSPoint(x: 200, y: 200)
        }

        let visibleFrame = screen.visibleFrame
        let originX = visibleFrame.midX - (panelSize.width / 2)
        let originY = visibleFrame.midY - (panelSize.height / 2) + 36
        return NSPoint(x: round(originX), y: round(originY))
    }

    private func screen(for point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.visibleFrame.contains(point) })
            ?? NSScreen.screens.first(where: { $0.frame.contains(point) })
            ?? NSScreen.main
    }
}
