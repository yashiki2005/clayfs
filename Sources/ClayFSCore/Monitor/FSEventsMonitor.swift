import Foundation
#if canImport(CoreServices)
import CoreServices
#endif

#if canImport(CoreServices)
public final class FSEventsMonitor: @unchecked Sendable {
    public let watchURL: URL
    private let debounceSeconds: TimeInterval
    private let onDebouncedChange: @Sendable () -> Void

    private var streamRef: FSEventStreamRef?
    private var debounceTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "top.yashiki.clayfs.fsevents", qos: .utility)
    private var isRunning = false

    private static func isIgnoredPath(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        for comp in components {
            if comp == ".clayfs" || comp == ".fseventsd" || comp == ".Trashes" || comp == ".Spotlight-V100" || comp == ".TemporaryItems" {
                return true
            }
        }
        return false
    }

    public init(
        watchURL: URL,
        debounceSeconds: TimeInterval = 5.0,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.watchURL = watchURL
        self.debounceSeconds = debounceSeconds
        self.onDebouncedChange = onChange
    }

    deinit {
        stop()
    }

    public func start() {
        queue.sync {
            guard !isRunning else { return }
            isRunning = true

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            let pathsToWatch = [watchURL.path] as CFArray
            let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)

            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
                    guard let info = clientCallBackInfo else { return }
                    let monitor = Unmanaged<FSEventsMonitor>.fromOpaque(info).takeUnretainedValue()

                    guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                    let hasRelevantChange = paths.contains { path in
                        !FSEventsMonitor.isIgnoredPath(path)
                    }

                    if hasRelevantChange {
                        monitor.scheduleDebouncedTrigger()
                    }
                },
                &context,
                pathsToWatch,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                1.0,
                flags
            ) else {
                return
            }

            self.streamRef = stream
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    public func stop() {
        queue.sync {
            guard isRunning else { return }
            isRunning = false

            if let timer = debounceTimer {
                timer.cancel()
                debounceTimer = nil
            }

            if let stream = streamRef {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                streamRef = nil
            }
        }
    }

    private func scheduleDebouncedTrigger() {
        debounceTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + debounceSeconds)
        // 発火したのが「今のタイマー」のときだけ、変更を通知して手放す。
        // 古いタイマーがキャンセル前に発火していた場合に、新しいタイマーを握ったままの
        // debounceTimer を nil にしてしまい、次の cancel() が空振りして二重に発火していた。
        timer.setEventHandler { [weak self, weak timer] in
            guard let self = self, let timer = timer else { return }
            guard self.debounceTimer === timer else { return }   // 古いタイマーの発火は捨てる
            self.debounceTimer = nil
            self.onDebouncedChange()
        }
        timer.resume()
        debounceTimer = timer
    }
}
#endif

/// Cross-platform polling monitor (used on Linux or fallback)
public final class PollingMonitor: @unchecked Sendable {
    public let watchURL: URL
    private let interval: TimeInterval
    private let onChange: @Sendable () -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "top.yashiki.clayfs.polling", qos: .utility)
    private var isRunning = false

    public init(
        watchURL: URL,
        interval: TimeInterval = 5.0,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.watchURL = watchURL
        self.interval = interval
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    public func start() {
        queue.sync {
            guard !isRunning else { return }
            isRunning = true

            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + interval, repeating: interval)
            t.setEventHandler { [weak self] in
                guard let self = self else { return }
                self.onChange()
            }
            t.resume()
            self.timer = t
        }
    }

    public func stop() {
        queue.sync {
            guard isRunning else { return }
            isRunning = false
            timer?.cancel()
            timer = nil
        }
    }
}
