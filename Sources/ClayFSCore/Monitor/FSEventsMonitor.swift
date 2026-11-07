import Foundation
import CoreServices

public final class FSEventsMonitor: @unchecked Sendable {
    private let watchURL: URL
    private let debounceSeconds: TimeInterval
    private let onDebouncedChange: @Sendable () -> Void

    private var streamRef: FSEventStreamRef?
    private var debounceTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "top.yashiki.clayfs.fsevents", qos: .utility)
    private var isRunning = false

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

        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, clientCallBackInfo, numEvents, eventPaths, _, _) in
                guard let info = clientCallBackInfo else { return }
                let monitor = Unmanaged<FSEventsMonitor>.fromOpaque(info).takeUnretainedValue()
                if let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] {
                    let hasUserChange = paths.contains {
                        !$0.contains("/.clayfs") &&
                        !$0.contains("/.fseventsd") &&
                        !$0.contains("/.Trashes") &&
                        !$0.contains("/.Spotlight-V100")
                    }
                    if hasUserChange {
                        monitor.handleChangeDetected()
                    }
                } else {
                    monitor.handleChangeDetected()
                }
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            flags
        )

        if let stream = streamRef {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    public func stop() {
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

    private func handleChangeDetected() {
        queue.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.debounceTimer?.cancel()

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + self.debounceSeconds)
            timer.setEventHandler { [weak self] in
                guard let self = self, self.isRunning else { return }
                self.debounceTimer = nil
                self.onDebouncedChange()
            }
            timer.resume()
            self.debounceTimer = timer
        }
    }
}
