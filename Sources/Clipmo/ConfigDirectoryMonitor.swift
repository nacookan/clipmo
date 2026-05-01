// `clipmo.conf` を含むベースディレクトリの変更通知を受ける最小の監視ラッパです。
import Dispatch
import Foundation

final class ConfigDirectoryMonitor {
    var onChange: (() -> Void)?

    private let directoryURL: URL
    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    deinit {
        stop()
    }

    /// menu polling に混ぜず、ファイルシステム通知でだけ再読込を起動します。
    func start() {
        guard source == nil else {
            return
        }

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend, .link],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.onChange?()
        }

        source.setCancelHandler {
            close(descriptor)
        }

        fileDescriptor = descriptor
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }
}
