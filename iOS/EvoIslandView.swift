import SwiftUI

// MARK: - Clean Dark Design System Tokens (M6.3)

enum EvoTheme {
    /// Main app background (#0E1015)
    static let background = Color(red: 14 / 255, green: 16 / 255, blue: 21 / 255)
    /// Elevated surface / container background (#14171F)
    static let surface = Color(red: 20 / 255, green: 23 / 255, blue: 31 / 255)
    /// Secondary panel / card / special key background (#1A1E28)
    static let panel = Color(red: 26 / 255, green: 30 / 255, blue: 40 / 255)
    /// Interactive button / primary key background (#222734)
    static let keySurface = Color(red: 34 / 255, green: 39 / 255, blue: 52 / 255)
    /// Pressed / highlighted key surface (#2C3344)
    static let keySurfaceActive = Color(red: 44 / 255, green: 51 / 255, blue: 68 / 255)
    /// Clean blue accent for active states (#2563EB)
    static let accent = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    /// Subtle 1px border
    static let border = Color.white.opacity(0.08)
    /// Slightly stronger border for active/focused containers
    static let borderStrong = Color.white.opacity(0.14)
    /// Primary text
    static let textPrimary = Color.white
    /// Secondary muted gray text
    static let textSecondary = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
    /// Tertiary subtle text
    static let textTertiary = Color(red: 100 / 255, green: 116 / 255, blue: 139 / 255)
}

// MARK: - Connection State Mapping

enum EvoConnectionState: Equatable {
    case connected
    case connecting
    case disconnected
    case error

    var label: String {
        switch self {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Disconnected"
        case .error:
            return "Error"
        }
    }

    var dotColor: Color {
        switch self {
        case .connected:
            return Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
        case .connecting:
            return Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
        case .disconnected:
            return Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
        case .error:
            return Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
        }
    }

    static func resolve(from connection: PadConnectionManager) -> EvoConnectionState {
        if connection.isAuthenticated {
            return .connected
        }
        let lower = connection.statusText.lowercased()
        if lower.contains("gagal") || lower.contains("ditolak") || lower.contains("tidak cocok") || lower.contains("error") {
            return .error
        }
        if connection.isConnected || lower.contains("menghubungkan") || lower.contains("autentikasi") {
            return .connecting
        }
        return .disconnected
    }
}

// MARK: - Evo Island Models

struct EvoIslandNotification: Identifiable, Equatable {
    let id: UUID
    let title: String
    let symbol: String
    let detail: String?
    let tint: Color

    init(
        id: UUID = UUID(),
        title: String,
        symbol: String,
        detail: String? = nil,
        tint: Color = EvoTheme.accent
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self.tint = tint
    }
}

struct EvoNowPlayingState: Equatable {
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String?
}

// MARK: - Animated Equalizer Waveform

struct EvoIslandWaveformView: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255))
                .frame(width: 2.5, height: animating ? 12 : 4)
                .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: animating)

            RoundedRectangle(cornerRadius: 1)
                .fill(Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255))
                .frame(width: 2.5, height: animating ? 5 : 14)
                .animation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true).delay(0.1), value: animating)

            RoundedRectangle(cornerRadius: 1)
                .fill(Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255))
                .frame(width: 2.5, height: animating ? 14 : 7)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(0.2), value: animating)
        }
        .frame(height: 14)
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Evo Island View (In-App Floating Morphing HUD Capsule)

struct EvoIslandView: View {
    @ObservedObject var connection: PadConnectionManager
    @Binding var isExpanded: Bool
    let onScanQR: () -> Void

    private var connectionState: EvoConnectionState {
        EvoConnectionState.resolve(from: connection)
    }

    private var displayMacName: String {
        let paired = (connection.currentPairedMacName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !paired.isEmpty {
            return paired
        }
        return connection.isAuthenticated ? "Mac" : "No Mac Paired"
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isExpanded.toggle()
            }
        } label: {
            capsuleContent
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("evopad.evoIsland.capsule")
    }

    @ViewBuilder
    private var capsuleContent: some View {
        if let notif = connection.activeNotification {
            // 1. Action Notification Morphing State
            HStack(spacing: 8) {
                Image(systemName: notif.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(notif.tint)
                    .frame(width: 20, height: 20)
                    .background(notif.tint.opacity(0.18), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(notif.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EvoTheme.textPrimary)
                        .lineLimit(1)

                    if let detail = notif.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(EvoTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Circle()
                    .fill(notif.tint)
                    .frame(width: 6, height: 6)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(EvoTheme.panel, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(notif.tint.opacity(0.4), lineWidth: 1)
            )
            .transition(.scale.combined(with: .opacity))

        } else if let np = connection.nowPlaying, np.isPlaying {
            // 2. Now Playing Mini Ticker State
            HStack(spacing: 8) {
                EvoIslandWaveformView()
                    .frame(width: 12, height: 12)

                HStack(spacing: 4) {
                    Text(np.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EvoTheme.textPrimary)
                        .lineLimit(1)

                    Text("·")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(EvoTheme.textTertiary)

                    Text(np.artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EvoTheme.textSecondary)
                        .lineLimit(1)
                }

                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(EvoTheme.accent)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(EvoTheme.panel, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(EvoTheme.borderStrong, lineWidth: 1)
            )
            .transition(.scale.combined(with: .opacity))

        } else {
            // 3. Default Connection Capsule State
            HStack(spacing: 10) {
                Circle()
                    .fill(connectionState.dotColor)
                    .frame(width: 8, height: 8)

                Text(displayMacName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EvoTheme.textPrimary)
                    .lineLimit(1)

                Text("·")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(EvoTheme.textTertiary)

                Text(connectionState.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(connectionState == .connected ? connectionState.dotColor : EvoTheme.textSecondary)
                    .lineLimit(1)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(EvoTheme.textSecondary)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(EvoTheme.panel, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isExpanded ? EvoTheme.borderStrong : EvoTheme.border, lineWidth: 1)
            )
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Evo Island Expanded Card

struct EvoIslandExpandedCard: View {
    @ObservedObject var connection: PadConnectionManager
    @Binding var isExpanded: Bool
    let onScanQR: () -> Void

    private var connectionState: EvoConnectionState {
        EvoConnectionState.resolve(from: connection)
    }

    private var displayMacName: String {
        let paired = (connection.currentPairedMacName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return paired.isEmpty ? "Belum dipasangkan" : paired
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(EvoTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(EvoTheme.border, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayMacName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(EvoTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(connectionState.dotColor)
                            .frame(width: 7, height: 7)
                        Text(connectionState.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(connectionState.dotColor)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(EvoTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(EvoTheme.keySurface, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Text(connection.statusText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(EvoTheme.textSecondary)
                .lineLimit(2)

            // Now Playing Media Section
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(
                                colors: [EvoTheme.accent.opacity(0.35), EvoTheme.surface],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 36, height: 36)
                        Image(systemName: "music.note")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(EvoTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(connection.nowPlaying?.title ?? "Media Player")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(EvoTheme.textPrimary)
                            .lineLimit(1)

                        Text(connection.nowPlaying?.artist ?? (connection.isAuthenticated ? "macOS Media" : "No Media"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(EvoTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if connection.nowPlaying?.isPlaying == true {
                        EvoIslandWaveformView()
                    }
                }

                // Playback Transport Buttons
                HStack(spacing: 8) {
                    Button {
                        connection.sendMediaKey(.previousTrack)
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(EvoTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        connection.sendMediaKey(.playPause)
                    } label: {
                        Image(systemName: (connection.nowPlaying?.isPlaying == true) ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(EvoTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(EvoTheme.accent, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        connection.sendMediaKey(.nextTrack)
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(EvoTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }

                // Volume Controls
                HStack(spacing: 6) {
                    Button {
                        connection.sendMediaKey(.mute)
                    } label: {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(EvoTheme.textSecondary)
                            .frame(width: 32, height: 26)
                            .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        connection.sendMediaKey(.volumeDown)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.1.fill")
                            Text("Vol -")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EvoTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        connection.sendMediaKey(.volumeUp)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.3.fill")
                            Text("Vol +")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EvoTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(EvoTheme.keySurface.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(EvoTheme.border, lineWidth: 1)
            )

            Divider()
                .overlay(EvoTheme.border)

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                        isExpanded = false
                    }
                    onScanQR()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 12, weight: .semibold))
                        Text(connection.isPairedWithMac ? "Pair Ulang QR" : "Scan QR")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(EvoTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(EvoTheme.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                if connection.isPairedWithMac {
                    Button {
                        connection.unpairCurrentMac()
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                            isExpanded = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Putuskan Pairing")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(EvoTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(EvoTheme.borderStrong, lineWidth: 1)
        )
        .accessibilityIdentifier("evopad.evoIsland.expanded")
    }
}
