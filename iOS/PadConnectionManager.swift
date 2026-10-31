import Combine
import Foundation
import Network

/// Owns Bonjour discovery of the Mac Helper and the TCP connection used to
/// send `PadCommand`s and receive `PadAcknowledgement`s back.
final class PadConnectionManager: ObservableObject {
    @Published private(set) var statusText = "Mencari Mac..."
    @Published private(set) var isConnected = false
    @Published private(set) var macFeedback = "Menunggu respons Mac"

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var lastEndpoint: NWEndpoint?
    private let networkQueue = DispatchQueue(label: "id.evonex.evopad.ios-network", qos: .userInteractive)

    // Diagnostics only — read/written exclusively on networkQueue, which is
    // also the queue `connection` was started with, so completions land here too.
    private var outstandingSends = 0

    func startDiscovery() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjour(type: PadProtocol.serviceType, domain: nil)
        let newBrowser = NWBrowser(for: descriptor, using: parameters)

        newBrowser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .failed(let error) = state {
                    self.statusText = "Pencarian gagal: \(error.localizedDescription)"
                }
            }
        }

        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, let first = results.first else { return }
            DispatchQueue.main.async {
                guard self.connection == nil else { return }
                self.statusText = "Mac ditemukan, menghubungkan..."
                self.connect(to: first.endpoint)
            }
        }

        browser = newBrowser
        newBrowser.start(queue: networkQueue)
        statusText = "Mencari Mac di jaringan lokal..."
    }

    /// Called from the main thread (CADisplayLink). JSON encoding and the
    /// actual NWConnection.send hop onto networkQueue so pointer/scroll
    /// commands never do that work on the UI thread.
    func send(_ command: PadCommand) {
        networkQueue.async { [weak self] in
            guard let self, let connection = self.connection else { return }
            guard var data = try? JSONEncoder().encode(command) else { return }
            data.append(0x0A)

            if command.type == .gesture, let direction = command.gestureDirection {
                PadLog.network("iPad: sending gesture command over TCP, direction=\(direction.rawValue)")
            }

            self.outstandingSends += 1
            if self.outstandingSends > 1 {
                PadLog.pointer("iPad: send backlog=\(self.outstandingSends)")
            }

            connection.send(
                content: data,
                contentContext: .defaultMessage,
                isComplete: false,
                completion: .contentProcessed { [weak self] error in
                    self?.networkQueue.async {
                        self?.outstandingSends -= 1
                    }
                    if let error, command.type == .gesture {
                        PadLog.network("iPad: gesture command send failed: \(error.localizedDescription)")
                    }
                }
            )
        }
    }

    private func connect(to endpoint: NWEndpoint) {
        lastEndpoint = endpoint
        connection?.cancel()

        let newConnection = NWConnection(
            to: endpoint,
            using: PadProtocol.lowLatencyTCPParameters()
        )
        connection = newConnection

        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            guard let newConnection else { return }

            switch state {
            case .ready:
                DispatchQueue.main.async { [weak self, weak newConnection] in
                    guard let self,
                          let activeConnection = newConnection,
                          self.connection === activeConnection else {
                        return
                    }

                    self.isConnected = true
                    self.statusText = "Terhubung ke Mac · target 60 Hz"
                    self.receiveAcknowledgements(on: activeConnection)
                }

            case .failed(let error):
                DispatchQueue.main.async { [weak self, weak newConnection] in
                    guard let self,
                          let failedConnection = newConnection,
                          self.connection === failedConnection else {
                        return
                    }

                    self.isConnected = false
                    self.statusText = "Koneksi gagal: \(error.localizedDescription)"
                    failedConnection.cancel()
                    self.connection = nil
                    self.retryConnection()
                }

            case .cancelled:
                DispatchQueue.main.async { [weak self, weak newConnection] in
                    guard let self,
                          let cancelledConnection = newConnection,
                          self.connection === cancelledConnection else {
                        return
                    }

                    self.isConnected = false
                    self.connection = nil
                }

            default:
                break
            }
        }

        newConnection.start(queue: networkQueue)
    }

    private func receiveAcknowledgements(
        on activeConnection: NWConnection,
        pending: Data = Data()
    ) {
        activeConnection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16_384
        ) { [weak self, weak activeConnection] data, _, isComplete, error in
            guard let self, let activeConnection else { return }

            var buffer = pending
            if let data {
                buffer.append(data)
            }

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)

                guard !line.isEmpty,
                      let acknowledgement = try? JSONDecoder().decode(
                        PadAcknowledgement.self,
                        from: line
                      ),
                      acknowledgement.kind == "gestureAck" else {
                    continue
                }

                PadLog.network("iPad: received gestureAck direction=\(acknowledgement.direction.rawValue) accepted=\(acknowledgement.accepted)")
                DispatchQueue.main.async { [weak self] in
                    self?.macFeedback = acknowledgement.message
                }
            }

            if error != nil || isComplete {
                activeConnection.cancel()
                return
            }

            self.receiveAcknowledgements(
                on: activeConnection,
                pending: buffer
            )
        }
    }

    private func retryConnection() {
        guard let endpoint = lastEndpoint else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.connection == nil else { return }
            self.statusText = "Mencoba menghubungkan kembali..."
            self.connect(to: endpoint)
        }
    }
}
