import AppKit
import SwiftUI

struct MacContentView: View {
    @ObservedObject var server: MacServer

    @AppStorage("gestureAction.up") private var swipeUpAction = PadSystemAction.missionControl.rawValue
    @AppStorage("gestureAction.down") private var swipeDownAction = PadSystemAction.appExpose.rawValue
    @AppStorage("gestureAction.left") private var swipeLeftAction = PadSystemAction.previousDesktop.rawValue
    @AppStorage("gestureAction.right") private var swipeRightAction = PadSystemAction.nextDesktop.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 3) {
                    Text("EvoPad Mac")
                        .font(.title2.weight(.semibold))
                    Text("Mac input receiver")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(server.isListening ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(server.isListening ? "Listener aktif" : "Menyiapkan")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            GroupBox("Koneksi") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(server.statusText, systemImage: "wifi")
                    Text("Perangkat: \(server.connectedDevice)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Bonjour: \(PadProtocol.serviceType) · TCP \(PadProtocol.port)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

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

                    Text("EvoPad mengirim Control-down → panah-down/up → Control-up. Pastikan shortcut Mission Control, Application windows, dan Spaces aktif di System Settings → Keyboard → Keyboard Shortcuts → Mission Control. Tes hanya memastikan event dikirim; macOS tidak memberi konfirmasi bahwa tampilan Mission Control benar-benar terbuka.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }

            HStack {
                Text("Fase 2 · Gesture Engine (4 jari)")
                Spacer()
                Button("Periksa izin") { server.refreshPermission() }
                    .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 500, minHeight: 560)
        .onAppear { server.start() }
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
