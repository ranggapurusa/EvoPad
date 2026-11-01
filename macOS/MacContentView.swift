import AppKit
import SwiftUI

struct MacContentView: View {
    @ObservedObject var server: MacServer

    @AppStorage("gestureAction.up") private var swipeUpAction = PadSystemAction.missionControl.rawValue
    @AppStorage("gestureAction.down") private var swipeDownAction = PadSystemAction.appExpose.rawValue
    @AppStorage("gestureAction.left") private var swipeLeftAction = PadSystemAction.previousDesktop.rawValue
    @AppStorage("gestureAction.right") private var swipeRightAction = PadSystemAction.nextDesktop.rawValue

    @State private var showingPairingQRSheet = false
    @State private var qrTimeRemaining = 60
    @State private var timerSubscription: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(Color.indigo, in: RoundedRectangle(cornerRadius: 15))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("EvoPad Mac")
                            .font(.title2.weight(.semibold))
                        Text("TLS 1.3 · Mutual Authentication")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(server.isListening ? Color.green : Color.orange)
                        .frame(width: 9, height: 9)
                    Text(server.isListening ? "TLS Listener Aktif" : "Menyiapkan")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                // Security & Pairing Section (M2)
                GroupBox("Keamanan & Pairing") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Sertifikat Server (SHA-256 Fingerprint)")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Text(server.certFingerprintHex.isEmpty ? "Identity belum siap" : server.certFingerprintHex)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            if server.certFingerprintHex.isEmpty {
                                Button("Muat Ulang Identity") {
                                    server.retryIdentityInitialization()
                                }
                                .buttonStyle(.bordered)
                            }
                            Button("Pairing iPad Baru") {
                                server.generateNewPairingQR()
                                startQRCountdown()
                                showingPairingQRSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.indigo)
                        }

                        Divider()

                        // Paired Devices List
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Perangkat Terdaftar (\(server.pairedDevices.count))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if !server.pairedDevices.isEmpty {
                                    Button("Cabut Semua") {
                                        server.revokeAllDevices()
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                }
                            }

                            if server.pairedDevices.isEmpty {
                                Text("Belum ada iPad yang dipairing.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.vertical, 2)
                            } else {
                                ForEach(server.pairedDevices) { device in
                                    HStack {
                                        Label(device.name, systemImage: "ipad")
                                            .font(.subheadline)
                                        Spacer()
                                        Text("Dipairing: \(device.pairedDate.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Button("Cabut") {
                                            server.revokeDevice(deviceId: device.deviceId)
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                // Connection Status
                GroupBox("Koneksi Aktif") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(server.statusText, systemImage: "wifi")
                        Text("Perangkat: \(server.connectedDevice)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("TLS 1.3 · Bonjour: \(PadProtocol.serviceType) · Port \(PadProtocol.port)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                // Input Feedback
                GroupBox("Input terakhir") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(server.lastInputText, systemImage: "waveform.path")
                            .font(.subheadline)
                        HStack {
                            Text("Pointer input rate")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(server.pointerInputHz) Hz · target 60 Hz")
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                // Accessibility Permission
                GroupBox("Izin Accessibility") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            server.hasAccessibilityPermission ? "Izin sudah aktif" : "Izin belum diberikan",
                            systemImage: server.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(server.hasAccessibilityPermission ? .green : .orange)

                        Text("macOS memerlukan izin ini agar EvoPad dapat menggerakkan kursor, mengirim klik, dan menjalankan shortcut gesture.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button("Minta izin") {
                                _ = server.requestAccessibilityPermission()
                                server.refreshPermission()
                            }
                            Button("Buka Pengaturan Sistem") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                // Four Finger Gestures Configuration
                GroupBox("Gesture empat jari") {
                    VStack(alignment: .leading, spacing: 12) {
                        gesturePicker("Atas", symbol: "arrow.up", direction: .up, value: $swipeUpAction)
                        gesturePicker("Bawah", symbol: "arrow.down", direction: .down, value: $swipeDownAction)
                        gesturePicker("Kiri", symbol: "arrow.left", direction: .left, value: $swipeLeftAction)
                        gesturePicker("Kanan", symbol: "arrow.right", direction: .right, value: $swipeRightAction)

                        HStack {
                            Button("Pulihkan default") {
                                swipeUpAction = PadSystemAction.missionControl.rawValue
                                swipeDownAction = PadSystemAction.appExpose.rawValue
                                swipeLeftAction = PadSystemAction.previousDesktop.rawValue
                                swipeRightAction = PadSystemAction.nextDesktop.rawValue
                            }
                            Button("Buka pengaturan shortcut") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 540, minHeight: 640)
        .onAppear { server.start() }
        // Pairing Approval Sheet / Alert
        .sheet(item: $server.pendingPairingRequest) { request in
            VStack(spacing: 16) {
                Image(systemName: "ipad.and.arrow.forward")
                    .font(.system(size: 40))
                    .foregroundStyle(.indigo)

                Text("Permintaan Pairing iPad")
                    .font(.headline)

                Text("iPad \"\(request.clientName)\" ingin terhubung dan mengontrol Mac ini melalui saluran terenkripsi TLS 1.3.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                HStack(spacing: 16) {
                    Button("Tolak", role: .cancel) {
                        server.approvePendingPairing(approved: false)
                    }
                    .buttonStyle(.bordered)

                    Button("Izinkan Pairing") {
                        server.approvePendingPairing(approved: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                }
            }
            .padding(24)
            .frame(width: 380)
        }
        // QR Code Display Sheet
        .sheet(isPresented: $showingPairingQRSheet) {
            VStack(spacing: 16) {
                Text("Pindai QR Code di iPad")
                    .font(.headline)

                Text("Buka aplikasi EvoPad di iPad Anda, lalu pilih 'Pindai QR' untuk pairing instan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let errorMessage = server.qrErrorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)

                        Text("Gagal Menyiapkan Pairing")
                            .font(.subheadline.weight(.semibold))

                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Coba Lagi") {
                            server.retryIdentityInitialization()
                            server.generateNewPairingQR()
                            startQRCountdown()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                    }
                    .frame(width: 260, height: 220)
                } else if qrTimeRemaining == 0 {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.xmark")
                            .font(.system(size: 36))
                            .foregroundStyle(.red)

                        Text("Kode QR Kedaluwarsa")
                            .font(.subheadline.weight(.semibold))

                        Text("Demi keamanan, kode QR hanya berlaku selama 60 detik.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Buat Ulang Kode QR") {
                            server.generateNewPairingQR()
                            startQRCountdown()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                    }
                    .frame(width: 260, height: 220)
                } else if let image = server.qrImage {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(8)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    HStack {
                        Image(systemName: "timer")
                        Text("Kode kedaluwarsa dalam \(qrTimeRemaining) detik")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(qrTimeRemaining > 10 ? Color.secondary : Color.red)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Menyiapkan kunci dan kode QR...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 220, height: 220)
                }

                Button("Tutup") {
                    stopQRCountdown()
                    showingPairingQRSheet = false
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(width: 340)
            .onChange(of: server.qrErrorMessage) { newValue in
                if newValue != nil {
                    stopQRCountdown()
                }
            }
        }
    }

    private func startQRCountdown() {
        stopQRCountdown()
        qrTimeRemaining = 60
        timerSubscription = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if qrTimeRemaining > 0 {
                qrTimeRemaining -= 1
            } else {
                timer.invalidate()
            }
        }
    }

    private func stopQRCountdown() {
        timerSubscription?.invalidate()
        timerSubscription = nil
    }

    @ViewBuilder
    private func gesturePicker(_ title: String, symbol: String, direction: PadGestureDirection, value: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbol)
                .frame(width: 82, alignment: .leading)
            Picker("Aksi", selection: value) {
                ForEach(PadSystemAction.allCases) { action in
                    Text("\(action.title)  ·  \(action.shortcutDescription)")
                        .tag(action.rawValue)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button("Tes") {
                server.testGesture(direction)
            }
            .controlSize(.small)
        }
    }
}
