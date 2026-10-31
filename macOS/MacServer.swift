import Combine
import Foundation
import Network

final class MacServer: ObservableObject {
    @Published private(set) var statusText = "Menyiapkan layanan..."
    @Published private(set) var connectedDevice = "Belum ada iPad"
    @Published private(set) var isListening = false
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var lastInputText = "Belum ada input diterima"
    @Published private(set) var pointerInputHz = 0

    private var pointerFrameCount = 0
    private var pointerRateWindowStart = DispatchTime.now().uptimeNanoseconds
    private let receivedRate = PadRateCounter(label: "Mac pointer received")
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let inputQueue = DispatchQueue(label: "id.evonex.evopad.mac-input", qos: .userInteractive)
    private let eventController = InputEventController()

    func start() {
        guard listener == nil else { return }
        refreshPermission()

        do {
            guard let port = NWEndpoint.Port(rawValue: PadProtocol.port) else {
                statusText = "Port tidak valid"
                return
            }

            let newListener = try NWListener(
                using: PadProtocol.lowLatencyTCPParameters(),
                on: port
            )
            let deviceName = Host.current().localizedName ?? "Mac"
            newListener.service = NWListener.Service(
                name: "EvoPad-\(deviceName)",
                type: PadProtocol.serviceType
            )

            newListener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isListening = true
                        self.statusText = "Siap — menunggu iPad"
                    case .failed(let error):
                        self.isListening = false
                        self.statusText = "Gagal membuka layanan: \(error.localizedDescription)"
                        self.listener?.cancel()
                        self.listener = nil
                    case .cancelled:
                        self.isListening = false
                        self.statusText = "Layanan dihentikan"
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                DispatchQueue.main.async {
                    self?.accept(connection)
                }
            }

            listener = newListener
            newListener.start(queue: .main)
        } catch {
            statusText = "Tidak dapat menjalankan server: \(error.localizedDescription)"
        }
    }

    func refreshPermission() {
        hasAccessibilityPermission = eventController.hasAccessibilityPermission
    }

    /// Runs the Mac-side shortcut test on the same serial input queue as pointer
    /// events so keyboard chords cannot interleave with mouse-button state.
    func testGesture(_ direction: PadGestureDirection) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            self.eventController.releaseAllButtons()
            let sent = self.eventController.performGesture(direction)
            DispatchQueue.main.async {
                self.lastInputText = sent
                    ? "Tes \(direction.title): event Control + panah dikirim"
                    : "Tes \(direction.title) gagal: periksa izin Accessibility atau shortcut"
            }
        }
    }

    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let granted = eventController.requestAccessibilityPermission()
        refreshPermission()
        return granted
    }

    private func accept(_ connection: NWConnection) {
        // A replaced client must never leave a mouse button held down.
        activeConnection?.cancel()
        activeConnection = connection
        connectedDevice = "iPad terhubung"
        statusText = "Terhubung — input diproses pada queue prioritas tinggi"

        inputQueue.async { [weak self] in
            self?.eventController.releaseAllButtons()
        }

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.connectedDevice = "iPad terhubung"
                    self.statusText = "Terhubung — menerima input"
                }
            case .failed, .cancelled:
                // State callbacks execute on inputQueue, so release is ordered
                // after all previously received pointer/button events.
                self.eventController.releaseAllButtons()
                DispatchQueue.main.async {
                    guard let connection, self.activeConnection === connection else { return }
                    self.lastInputText = "Koneksi terputus — tombol mouse dilepas"
                    self.activeConnection = nil
                    self.connectedDevice = "Belum ada iPad"
                    self.statusText = self.isListening ? "Siap — menunggu iPad" : "Koneksi terputus"
                }
            default:
                break
            }
        }

        connection.start(queue: inputQueue)
        receive(on: connection, pending: Data())
    }

    private func receive(on connection: NWConnection, pending: Data) {
        // NWConnection receive callback runs on inputQueue. JSON decoding and
        // CGEvent posting stay off the Mac Helper's UI thread.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }

            var buffer = pending
            if let data {
                buffer.append(data)
            }

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)

                guard !line.isEmpty,
                      let command = try? JSONDecoder().decode(PadCommand.self, from: line) else {
                    continue
                }

                if command.type == .gesture, let direction = command.gestureDirection {
                    PadLog.network("Mac: received gesture command direction=\(direction.rawValue)")
                    self.eventController.releaseAllButtons()
                    let sent = self.eventController.performGesture(direction)
                    let message = sent
                        ? "Mac Helper menerima \(direction.title) dan mem-post Control + panah ke sesi macOS. Jika UI tidak berubah, periksa shortcut Mission Control/Spaces di macOS."
                        : "Mac Helper menerima \(direction.title), tetapi gagal membuat event keyboard. Periksa izin Accessibility."
                    self.sendGestureAcknowledgement(
                        PadAcknowledgement.gesture(direction: direction, accepted: sent, message: message),
                        over: connection
                    )
                    DispatchQueue.main.async {
                        self.lastInputText = sent
                            ? "\(direction.title): event dipost ke sesi macOS"
                            : "\(direction.title): event gagal dibuat/dipost"
                    }
                } else {
                    // Spike detector, not a constant log: only decode+post
                    // stalls above 8ms (half a 60Hz frame) are logged, since
                    // that is the kind of one-off hitch that reads as
                    // "choppy" pointer motion.
                    let start = DispatchTime.now().uptimeNanoseconds
                    self.eventController.handle(command)
                    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000
                    if elapsedMs > 8 {
                        PadLog.pointer("Mac: \(command.type.rawValue) decode+post took \(String(format: "%.1f", elapsedMs))ms")
                    }
                    self.updateInputFeedback(for: command)
                }
            }

            if error != nil || isComplete {
                self.eventController.releaseAllButtons()
                connection.cancel()
                return
            }

            self.receive(on: connection, pending: buffer)
        }
    }

    private func sendGestureAcknowledgement(_ acknowledgement: PadAcknowledgement, over connection: NWConnection) {
        guard var data = try? JSONEncoder().encode(acknowledgement) else { return }
        data.append(0x0A)
        connection.send(
            content: data,
            contentContext: .defaultMessage,
            isComplete: false,
            completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                DispatchQueue.main.async {
                    self?.lastInputText = "ACK gagal dikirim ke iPad: \(error.localizedDescription)"
                }
            }
        )
    }

    private func recordPointerFrame() {
        receivedRate.tick()
        pointerFrameCount += 1
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now &- pointerRateWindowStart
        guard elapsed >= 1_000_000_000 else { return }

        let measuredHz = Int((Double(pointerFrameCount) / (Double(elapsed) / 1_000_000_000)).rounded())
        pointerFrameCount = 0
        pointerRateWindowStart = now
        DispatchQueue.main.async { [weak self] in
            self?.pointerInputHz = measuredHz
        }
    }

    private func updateInputFeedback(for command: PadCommand) {
        if command.type == .move {
            recordPointerFrame()
        }

        let message: String?
        switch command.type {
        case .buttonDown:
            message = "Drag diterima: tombol kiri ditahan"
        case .buttonUp:
            message = "Drag selesai: tombol mouse dilepas"
        case .click:
            message = command.button == .right ? "Klik kanan diterima" : "Klik kiri diterima"
        case .move, .scroll, .gesture:
            message = nil
        }

        guard let message else { return }
        DispatchQueue.main.async { [weak self] in
            self?.lastInputText = message
        }
    }
}
