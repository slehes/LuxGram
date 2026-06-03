import Foundation
import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit
#if canImport(SGSimpleSettings)
import SGSimpleSettings
#endif

private typealias SignalKitTimer = SwiftSignalKit.Timer

private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)

    private var shouldKeepOnlinePresenceDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?

    private var ghostOfflineTimer: SignalKitTimer?

    private var wasOnline: Bool = false

    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        self.queue = queue
        self.network = network

        self.shouldKeepOnlinePresenceDisposable = (shouldKeepOnlinePresence
        |> distinctUntilChanged
        |> deliverOn(self.queue)).start(next: { [weak self] value in
            guard let `self` = self else {
                return
            }
            if self.wasOnline != value {
                self.wasOnline = value
                self.updatePresence(value)
            }
        })
    }

    deinit {
        assert(self.queue.isCurrent())
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.onlineTimer?.invalidate()
        self.ghostOfflineTimer?.invalidate()
    }

    /// Returns true if any ghost mode option is currently active.
    private func isGhostModeActive() -> Bool {
        #if canImport(SGSimpleSettings)
        return SGSimpleSettings.shared.disableOnlineStatus ||
               SGSimpleSettings.shared.ghostModeMessageSendDelaySeconds > 0
        #else
        return false
        #endif
    }

    /// Sends a single offline packet to the server (suppresses online appearance).
    private func sendOfflinePacket() {
        let _ = (self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }).start()
    }

    /// Starts the periodic offline-packet timer (AyuGram sends every 3s, we use 5s to be less aggressive).
    /// While this timer is running the user will always appear offline to others,
    /// even if the MTProto layer briefly marks them as online during a message upload.
    private func startGhostOfflineTimer() {
        // Send immediately to cover any online flash
        self.sendOfflinePacket()

        self.ghostOfflineTimer?.invalidate()
        let timer = SignalKitTimer(timeout: 5.0, repeat: true, completion: { [weak self] in
            self?.sendOfflinePacket()
        }, queue: self.queue)
        self.ghostOfflineTimer = timer
        timer.start()
    }

    private func stopGhostOfflineTimer() {
        self.ghostOfflineTimer?.invalidate()
        self.ghostOfflineTimer = nil
    }

    private func updatePresence(_ isOnline: Bool) {
        #if canImport(SGSimpleSettings)
        if self.isGhostModeActive() {
            if isOnline {
                // App came to foreground with ghost mode on:
                // start periodic offline timer to suppress any online appearance,
                // including flashes caused by MTProto during ghost-delay message sends.
                self.startGhostOfflineTimer()
            } else {
                // App went to background: stop timer, send one final offline packet.
                self.stopGhostOfflineTimer()
                self.sendOfflinePacket()
            }
            return
        } else {
            // Ghost mode just disabled — stop timer and fall through to normal logic.
            self.stopGhostOfflineTimer()
        }
        #endif

        let request: Signal<Api.Bool, MTRpcError>
        if isOnline {
            let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.updatePresence(true)
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
        } else {
            self.onlineTimer?.invalidate()
            self.onlineTimer = nil
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(completed: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isPerformingUpdate.set(false)
        }))
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>

    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network)
        })
    }

    func isPerformingUpdate() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.isPerformingUpdate.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
}
