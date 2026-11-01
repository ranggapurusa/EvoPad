import SwiftUI

struct PadContentView: View {
    @StateObject private var connection = PadConnectionManager()
    @State private var inputFeedback = "Siap menerima gesture"
    @State private var showingQRScanner = false

    var body: some View {
        VStack(spacing: 14) {
            // Top Bar
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("EvoPad")
                            .font(.headline)
                            .foregroundStyle(.white)
                        if connection.isAuthenticated {
                            Text("TLS 1.3")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                    Text(connection.statusText)
                        .font(.caption)
                        .foregroundStyle(connection.isAuthenticated ? .green : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    showingQRScanner = true
                } label: {
                    Label("Pindai QR", systemImage: "qrcode.viewfinder")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.indigo)

                Circle()
                    .fill(connection.isAuthenticated ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(connection.isAuthenticated ? "CONNECTED" : (connection.isConnected ? "AUTHENTICATING" : "SEARCHING"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
            }

            TrackpadSurface(onCommand: { command in
                connection.send(command)
            }, onStatus: { message in
                inputFeedback = message
            })
            .overlay(alignment: .topLeading) {
                Text("TRACKPAD")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.30))
                    .padding(18)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                Text("1 jari: kursor  ·  2 jari: scroll  ·  3 jari: drag  ·  4 jari: Mac gestures")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(16)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 5) {
                Text(inputFeedback)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                    .accessibilityIdentifier("evopad.inputFeedback")

                Text("Mac: \(connection.macFeedback)")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.48))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                    .accessibilityIdentifier("evopad.macFeedback")
            }

            HStack(spacing: 12) {
                Button {
                    connection.send(.click(.left))
                } label: {
                    Label("Left Click", systemImage: "cursorarrow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.indigo)

                Button {
                    connection.send(.click(.right))
                } label: {
                    Label("Right Click", systemImage: "cursorarrow.click.2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .controlSize(.large)
        }
        .padding(18)
        .background(Color(red: 0.055, green: 0.06, blue: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { connection.startDiscovery() }
        .sheet(isPresented: $showingQRScanner) {
            NavigationStack {
                PadQRScannerView(onScan: { qrData in
                    showingQRScanner = false
                    connection.pairWithQR(qrData: qrData)
                }, onCancel: {
                    showingQRScanner = false
                })
                .navigationTitle("Pindai Kode QR Mac")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Batal") {
                            showingQRScanner = false
                        }
                    }
                }
            }
        }
    }
}
