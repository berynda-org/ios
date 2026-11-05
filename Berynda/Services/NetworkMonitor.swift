import Combine
import Foundation
import Network

enum NetworkStatus: Equatable {
    case checking
    case online
    case offline
}

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var status: NetworkStatus = .checking

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "org.berynda.ios.network-monitor")

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let nextStatus: NetworkStatus = path.status == .satisfied ? .online : .offline
            Task { @MainActor [weak self] in
                self?.status = nextStatus
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
