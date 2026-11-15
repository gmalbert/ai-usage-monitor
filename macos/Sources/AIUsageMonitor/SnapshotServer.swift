import Foundation
import Network
import AIUsageMonitorCore

/// A minimal localhost-only HTTP endpoint serving the latest usage snapshot
/// so the widget extension can read data when the App Group container is not
/// available (development builds without a provisioning profile). It serves
/// one GET path with no secrets; usage percentages and reset times only.
final class SnapshotServer: @unchecked Sendable {
    static let shared = SnapshotServer()

    private var listener: NWListener?
    private let lock = NSLock()
    private var payload = Data()
    private let queue = DispatchQueue(label: "aiusagemonitor.snapshotserver")

    var isRunning: Bool {
        listener?.state == .ready
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Loopback only: the snapshot is never exposed off-machine.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: .any
        )
        do {
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: LocalSnapshotSync.port)!)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            // A stale instance may still hold the port; the widget falls back
            // to the App Group channel, so failure here is not fatal.
        }
    }

    func update(_ snapshot: UsageSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        payload = (try? JSONEncoder.withISODates().encode(snapshot)) ?? Data()
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        listener?.cancel()
        listener = nil
    }

    /// True when another instance of this app is already serving the
    /// loopback snapshot endpoint. Used as a single-instance guard.
    static func isSiblingInstanceRunning() async -> Bool {
        var request = URLRequest(url: LocalSnapshotSync.url)
        request.timeoutInterval = 1.5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              (try? JSONDecoder.withISODates().decode(UsageSnapshot.self, from: data)) != nil else {
            return false
        }
        return true
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection, accumulated: Data())
    }

    private func receiveRequest(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var request = accumulated
            if let data {
                request.append(data)
            }
            if error == nil, !isComplete, !request.contains(Data("\r\n\r\n".utf8)), request.count < 16_384 {
                self.receiveRequest(connection, accumulated: request)
                return
            }
            let response: String
            if String(decoding: request, as: UTF8.self).hasPrefix("GET \(LocalSnapshotSync.path)") {
                response = "HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(self.payload.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(response.utf8) + self.payload, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else {
                response = "HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }
}
