// NSPasteboard を軽く polling して、text / file / image の変化だけを observation へ変換します。
// 重い OCR はここで background task へ逃がし、監視 loop 自体は軽く保ちます。
import AppKit

@MainActor
final class ClipboardMonitor: NSObject {
    var onObservation: ((ClipboardObservation) -> Void)?
    var ocrLanguages: [String] = []

    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var ignoredSignatures: [ClipboardContentSignature] = []
    private var ocrTask: Task<Void, Never>?
    private var timer: Timer?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
        super.init()
    }

    /// 変化なしの fast path をできるだけ軽くするため、短い interval の単純 polling にしています。
    func start(interval: TimeInterval = 0.3) {
        stop()

        let timer = Timer(timeInterval: interval, target: self, selector: #selector(handleTimerFire), userInfo: nil, repeats: true)
        timer.tolerance = interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        ocrTask?.cancel()
        ocrTask = nil
        timer?.invalidate()
        timer = nil
    }

    /// app 自身が clipboard を書き戻した直後は、同じ内容を履歴へ二重登録しないために抑止します。
    func ignoreNextChange(matching signature: ClipboardContentSignature) {
        ignoredSignatures.append(signature)
    }

    @objc private func handleTimerFire() {
        autoreleasepool {
            let currentChangeCount = pasteboard.changeCount
            guard currentChangeCount != lastChangeCount else {
                return
            }

            lastChangeCount = currentChangeCount
            ocrTask?.cancel()
            ocrTask = nil

            if let observation = ClipboardCaptureService.fileObservation(from: pasteboard) {
                handleObservation(observation)
                return
            }

            if let imageSnapshot = ImageOCRService.imageSnapshot(from: pasteboard) {
                startOCRIfNeeded(for: imageSnapshot, changeCount: currentChangeCount)
                return
            }

            if let observation = ClipboardCaptureService.textObservation(from: pasteboard) {
                handleObservation(observation)
            }
        }
    }

    private func startOCRIfNeeded(for imageSnapshot: ClipboardImageSnapshot, changeCount: Int) {
        // OCR は比較的重いので background へ逃がしつつ、
        // その間に clipboard が別内容へ変わっていたら結果を捨てます。
        ocrTask = Task { [weak self] in
            guard let self else {
                return
            }

            let recognizedText = await ImageOCRService.recognizeText(
                from: imageSnapshot.data,
                preferredLanguageIdentifiers: ocrLanguages
            )
            guard !Task.isCancelled else {
                return
            }

            guard pasteboard.changeCount == changeCount else {
                return
            }

            let observation = ClipboardCaptureService.imageObservation(from: imageSnapshot, recognizedText: recognizedText)
            handleObservation(observation)
        }
    }

    private func handleObservation(_ observation: ClipboardObservation) {
        if let index = ignoredSignatures.firstIndex(of: observation.primarySignature) {
            ignoredSignatures.remove(at: index)
            return
        }

        onObservation?(observation)
    }
}
