import AppKit
import SwiftUI

// MARK: - Navigation Tabs
enum MacNavTab: String, CaseIterable, Identifiable {
    case home = "Beranda"
    case pairing = "Pasangkan"
    case devices = "Perangkat"
    case settings = "Pengaturan"
    case about = "Tentang"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .pairing: return "qrcode.viewfinder"
        case .devices: return "laptopcomputer"
        case .settings: return "gearshape.fill"
        case .about: return "info.circle.fill"
        }
    }
}

// MARK: - Design Theme
enum MacTheme {
    static let background = Color(red: 12 / 255, green: 16 / 255, blue: 27 / 255)
    static let sidebarBackground = Color(red: 16 / 255, green: 22 / 255, blue: 35 / 255)
    static let cardBackground = Color(red: 21 / 255, green: 27 / 255, blue: 41 / 255)
    static let cardHover = Color(red: 27 / 255, green: 35 / 255, blue: 52 / 255)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.16)
    static let accent = Color(red: 29 / 255, green: 104 / 255, blue: 254 / 255)
    static let success = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let textTertiary = Color.white.opacity(0.40)
}

struct MacContentView: View {
    @ObservedObject var server: MacServer

    // Gestures configuration
    @AppStorage("gestureAction.up") private var swipeUpAction = PadSystemAction.missionControl.rawValue
    @AppStorage("gestureAction.down") private var swipeDownAction = PadSystemAction.appExpose.rawValue
    @AppStorage("gestureAction.left") private var swipeLeftAction = PadSystemAction.previousDesktop.rawValue
    @AppStorage("gestureAction.right") private var swipeRightAction = PadSystemAction.nextDesktop.rawValue

    // Service toggles
    @AppStorage("service.trackpad.enabled") private var isTrackpadEnabled = true
    @AppStorage("service.keyboard.enabled") private var isKeyboardEnabled = true
    @AppStorage("service.shortcut.enabled") private var isShortcutEnabled = true
    @AppStorage("service.macro.enabled") private var isMacroEnabled = true

    @State private var activeTab: MacNavTab = .home
    @State private var qrTimeRemaining = 60
    @State private var timerSubscription: Timer?
    @State private var isSidebarVisible = true

    var body: some View {
        ZStack {
            MacTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Custom Title Bar
                topTitleBar

                Divider()
                    .background(MacTheme.border)

                // Main Split Area: Sidebar + Content Canvas
                HStack(spacing: 0) {
                    if isSidebarVisible {
                        sidebarView
                            .frame(width: 200)
                            .background(MacTheme.sidebarBackground)

                        Divider()
                            .background(MacTheme.border)
                    }

                    mainContentArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 880, minHeight: 620)
        .preferredColorScheme(.dark)
        .onAppear {
            if let icon = NSImage(named: "AppIcon") {
                NSApplication.shared.applicationIconImage = icon
            }
            server.start()
            if server.qrImage == nil {
                server.generateNewPairingQR()
                startQRCountdown()
            }
        }
        // Pairing Approval Sheet
        .sheet(item: $server.pendingPairingRequest) { (request: MacServer.PendingPairingApproval) in
            pairingApprovalSheet(request: request)
        }
    }

    // MARK: - Top Window Title Bar

    private var topTitleBar: some View {
        HStack(spacing: 12) {
            // Window Traffic Lights Spacer
            Spacer().frame(width: 68)

            Spacer()

            Text("EvoPad Helper")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)

            Spacer()

            // Sidebar Layout Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: isSidebarVisible ? "sidebar.left" : "sidebar.leading")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(MacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(MacTheme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(isSidebarVisible ? "Sembunyikan Sidebar" : "Tampilkan Sidebar")

            // Global Master Service Switch
            Toggle(
                "",
                isOn: Binding(
                    get: { server.isListening },
                    set: { shouldListen in
                        if shouldListen {
                            server.start()
                        } else {
                            server.stop()
                        }
                    }
                )
            )
            .toggleStyle(SwitchToggleStyle(tint: MacTheme.accent))
            .labelsHidden()
            .controlSize(.mini)
            .help(server.isListening ? "Hentikan Layanan Server" : "Jalankan Layanan Server")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MacTheme.background)
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header: App Logo Mark & Name
            HStack(spacing: 10) {
                EvoPadLogoMark(size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("EvoPad")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(MacTheme.textPrimary)

                    Text("Mac Helper")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            // Navigation List
            VStack(spacing: 4) {
                ForEach(MacNavTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            activeTab = tab
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 20)

                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: activeTab == tab ? .semibold : .medium))

                            Spacer()
                        }
                        .foregroundStyle(activeTab == tab ? Color.white : MacTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            activeTab == tab ? MacTheme.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Footer Status Badge: "● Layanan Aktif"
            HStack(spacing: 8) {
                Circle()
                    .fill(server.isListening ? MacTheme.success : Color.orange)
                    .frame(width: 8, height: 8)

                Text(server.isListening ? "Layanan Aktif" : "Layanan Nonaktif")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(MacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(MacTheme.border, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Main Content Switcher

    @ViewBuilder
    private var mainContentArea: some View {
        switch activeTab {
        case .home:
            dashboardHomeView
        case .pairing:
            pairingManagementView
        case .devices:
            devicesManagementView
        case .settings:
            settingsConfigView
        case .about:
            aboutInformationView
        }
    }

    // MARK: - Tab 1: Dashboard Home (Image #1 Match)

    private var dashboardHomeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Hero Card: MacBook Mockup + Status Indicator
                heroStatusCard

                // 2. Middle Row: QR Code Pairing Card + 3 Info Tiles
                HStack(alignment: .top, spacing: 14) {
                    qrPairingCard
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 10) {
                        infoStatusTile(
                            icon: "wifi",
                            title: "Koneksi",
                            subtitle: server.connectedDevice != "Belum ada iPad" ? "Terhubung (\(server.connectedDevice))" : "Menunggu"
                        )

                        infoStatusTile(
                            icon: "lock.fill",
                            title: "Keamanan",
                            subtitle: "Terenkripsi"
                        )

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                activeTab = .devices
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.06))
                                        .frame(width: 36, height: 36)

                                    Image(systemName: "square.grid.2x2")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(MacTheme.textPrimary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Perangkat Terhubung")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(MacTheme.textPrimary)

                                    Text("\(server.pairedDevices.count) perangkat")
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundStyle(MacTheme.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(MacTheme.textTertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(MacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(MacTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                }

                // 3. Bottom Section: Layanan (Services Grid)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Layanan")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MacTheme.textPrimary)
                        .padding(.top, 4)

                    HStack(spacing: 12) {
                        serviceToggleCard(
                            title: "Trackpad",
                            subtitle: "Kontrol pointer & gesture",
                            icon: "cursorarrow",
                            isOn: $isTrackpadEnabled
                        )

                        serviceToggleCard(
                            title: "Keyboard",
                            subtitle: "Input keyboard",
                            icon: "keyboard",
                            isOn: $isKeyboardEnabled
                        )

                        serviceToggleCard(
                            title: "Shortcut",
                            subtitle: "Tombol cepat",
                            icon: "command",
                            isOn: $isShortcutEnabled
                        )

                        serviceToggleCard(
                            title: "Macro",
                            subtitle: "Jalankan perintah",
                            icon: "square.3.layers.3d",
                            isOn: $isMacroEnabled
                        )
                    }
                }
            }
            .padding(18)
        }
    }

    // MARK: - Hero Card (Top Banner with MacBook Mockup)

    private var heroStatusCard: some View {
        ZStack(alignment: .leading) {
            // Navy Gradient Background with Lighting Effect
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 16 / 255, green: 34 / 255, blue: 64 / 255),
                            Color(red: 10 / 255, green: 20 / 255, blue: 40 / 255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // Subtle dynamic blue mesh glow on right side
                    GeometryReader { geo in
                        Path { path in
                            path.move(to: CGPoint(x: geo.size.width * 0.45, y: 0))
                            path.addCurve(
                                to: CGPoint(x: geo.size.width, y: geo.size.height * 0.7),
                                control1: CGPoint(x: geo.size.width * 0.65, y: geo.size.height * 0.1),
                                control2: CGPoint(x: geo.size.width * 0.85, y: geo.size.height * 0.9)
                            )
                            path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 29 / 255, green: 104 / 255, blue: 254 / 255).opacity(0.18),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(MacTheme.border, lineWidth: 1)
                )

            HStack(spacing: 24) {
                // MacBook Vector Graphic
                MacBookGraphicView()
                    .padding(.leading, 18)

                // Status & Description
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(server.connectedDevice != "Belum ada iPad" ? MacTheme.success : (server.isListening ? MacTheme.success : Color.orange))
                            .frame(width: 10, height: 10)

                        Text(server.connectedDevice != "Belum ada iPad" ? "Terhubung ke \(server.connectedDevice)" : (server.isListening ? "Siap Terhubung" : "Layanan Nonaktif"))
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(MacTheme.textPrimary)
                    }

                    Text(server.connectedDevice != "Belum ada iPad" ? "Koneksi TLS 1.3 Terverifikasi & Aktif" : "Menunggu koneksi dari EvoPad")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)

                    // Pill Badge: Server Aktif • Port 8767
                    HStack(spacing: 6) {
                        Image(systemName: "wifi")
                            .font(.system(size: 11, weight: .semibold))

                        Text(server.isListening ? "Server Aktif" : "Server Terhenti")
                            .font(.system(size: 11, weight: .medium))

                        Text("•")
                            .font(.system(size: 10))
                            .opacity(0.5)

                        Text("Port \(PadProtocol.port)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(MacTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.35), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .padding(.top, 4)
                }

                Spacer()
            }
            .padding(.vertical, 16)
        }
        .frame(height: 148)
    }

    // MARK: - QR Code Pairing Card

    private var qrPairingCard: some View {
        VStack(spacing: 12) {
            Text("Pasangkan EvoPad")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)

            ZStack {
                if let qrImage = server.qrImage, qrTimeRemaining > 0 {
                    ZStack {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 132, height: 132)
                            .padding(8)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Center Logo Mark Overlay
                        EvoPadLogoMark(size: 26)
                            .shadow(color: Color.black.opacity(0.3), radius: 3)
                    }
                } else if qrTimeRemaining == 0 {
                    VStack(spacing: 6) {
                        Image(systemName: "clock.badge.xmark")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.red.opacity(0.8))

                        Text("Kode Kedaluwarsa")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    .frame(width: 148, height: 148)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Membuat QR...")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.textTertiary)
                    }
                    .frame(width: 148, height: 148)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }
            }

            // Regenerate / Show Code Button
            Button {
                server.generateNewPairingQR()
                startQRCountdown()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))

                    Text(qrTimeRemaining > 0 ? "Tampilkan Kode (\(qrTimeRemaining)s)" : "Tampilkan Kode")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(MacTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(MacTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(MacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(MacTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Info Tile

    private func infoStatusTile(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(MacTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(MacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(MacTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Service Toggle Card

    private func serviceToggleCard(
        title: String,
        subtitle: String,
        icon: String,
        isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary)

                Spacer()

                Toggle("", isOn: isOn)
                    .toggleStyle(SwitchToggleStyle(tint: MacTheme.success))
                    .labelsHidden()
                    .controlSize(.mini)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(MacTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(MacTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Tab 2: Pairing Management View

    private var pairingManagementView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pasangkan EvoPad iPad")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MacTheme.textPrimary)

                Text("Pindai kode QR dari aplikasi EvoPad iPad untuk mengotorisasi koneksi TLS 1.3.")
                    .font(.subheadline)
                    .foregroundStyle(MacTheme.textSecondary)

                HStack(alignment: .top, spacing: 18) {
                    qrPairingCard
                        .frame(width: 260)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Detail Sertifikat Keamanan")
                            .font(.headline)
                            .foregroundStyle(MacTheme.textPrimary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fingerprint Sertifikat Server:")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(MacTheme.textSecondary)

                            Text(server.certFingerprintHex.isEmpty ? "Identity belum siap" : server.certFingerprintHex)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MacTheme.textPrimary)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                .textSelection(.enabled)
                        }

                        if server.certFingerprintHex.isEmpty {
                            Button("Muat Ulang Identity") {
                                server.retryIdentityInitialization()
                            }
                            .buttonStyle(.bordered)
                        }

                        Divider().background(MacTheme.border)

                        Text("Panduan Pairing:")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MacTheme.textPrimary)

                        Text("1. Pastikan Mac dan iPad berada dalam jaringan Wi-Fi lokal yang sama.\n2. Buka aplikasi EvoPad di iPad Anda.\n3. Ketuk ikon QR Code di bagian atas untuk memindai kode di samping.")
                            .font(.caption)
                            .foregroundStyle(MacTheme.textSecondary)
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .background(MacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(MacTheme.border, lineWidth: 1)
                    )
                }
            }
            .padding(20)
        }
    }

    // MARK: - Tab 3: Devices Management View

    private var devicesManagementView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Perangkat Terdaftar")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(MacTheme.textPrimary)

                        Text("Daftar iPad yang telah memiliki sertifikat pairing terenkripsi.")
                            .font(.subheadline)
                            .foregroundStyle(MacTheme.textSecondary)
                    }

                    Spacer()

                    if !server.pairedDevices.isEmpty {
                        Button("Cabut Semua Perangkat") {
                            server.revokeAllDevices()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }

                if server.pairedDevices.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "ipad")
                            .font(.system(size: 40))
                            .foregroundStyle(MacTheme.textTertiary)

                        Text("Belum ada iPad yang dipairing")
                            .font(.headline)
                            .foregroundStyle(MacTheme.textSecondary)

                        Text("Buka tab Pasangkan untuk menghubungkan iPad pertama Anda.")
                            .font(.caption)
                            .foregroundStyle(MacTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(MacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(MacTheme.border, lineWidth: 1)
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(server.pairedDevices) { device in
                            HStack(spacing: 14) {
                                Image(systemName: "ipad")
                                    .font(.system(size: 22))
                                    .foregroundStyle(MacTheme.accent)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(MacTheme.textPrimary)

                                    Text("Dipairing: \(device.pairedDate.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundStyle(MacTheme.textSecondary)
                                }

                                Spacer()

                                Button("Cabut Izin") {
                                    server.revokeDevice(deviceId: device.deviceId)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .controlSize(.small)
                            }
                            .padding(14)
                            .background(MacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(MacTheme.border, lineWidth: 1)
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Tab 4: Settings & Permissions View

    private var settingsConfigView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Pengaturan & Izin Sistem")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MacTheme.textPrimary)

                // Accessibility Permission Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: server.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(server.hasAccessibilityPermission ? MacTheme.success : Color.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.hasAccessibilityPermission ? "Izin Aksesibilitas Aktif" : "Izin Aksesibilitas Diperlukan")
                                .font(.headline)
                                .foregroundStyle(MacTheme.textPrimary)

                            Text("macOS memerlukan izin ini agar EvoPad dapat menggerakkan kursor dan mengetik.")
                                .font(.caption)
                                .foregroundStyle(MacTheme.textSecondary)
                        }

                        Spacer()

                        Button("Minta Izin") {
                            _ = server.requestAccessibilityPermission()
                            server.refreshPermission()
                        }
                        .buttonStyle(.bordered)

                        Button("Buka Pengaturan Sistem") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MacTheme.accent)
                    }
                }
                .padding(16)
                .background(MacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(MacTheme.border, lineWidth: 1)
                )

                // Four Finger Gestures
                VStack(alignment: .leading, spacing: 12) {
                    Text("Konfigurasi Gesture 4 Jari")
                        .font(.headline)
                        .foregroundStyle(MacTheme.textPrimary)

                    gesturePickerRow("Swipe Atas", symbol: "arrow.up", direction: .up, value: $swipeUpAction)
                    gesturePickerRow("Swipe Bawah", symbol: "arrow.down", direction: .down, value: $swipeDownAction)
                    gesturePickerRow("Swipe Kiri", symbol: "arrow.left", direction: .left, value: $swipeLeftAction)
                    gesturePickerRow("Swipe Kanan", symbol: "arrow.right", direction: .right, value: $swipeRightAction)

                    HStack {
                        Button("Pulihkan Default") {
                            swipeUpAction = PadSystemAction.missionControl.rawValue
                            swipeDownAction = PadSystemAction.appExpose.rawValue
                            swipeLeftAction = PadSystemAction.previousDesktop.rawValue
                            swipeRightAction = PadSystemAction.nextDesktop.rawValue
                        }
                        .buttonStyle(.bordered)

                        Button("Pengaturan Shortcut macOS") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.small)
                }
                .padding(16)
                .background(MacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(MacTheme.border, lineWidth: 1)
                )

                // Shortcut Testing Grid
                VStack(alignment: .leading, spacing: 10) {
                    Text("Uji Coba Pengiriman Shortcut")
                        .font(.headline)
                        .foregroundStyle(MacTheme.textPrimary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                        ForEach(PadStandardShortcut.allCases) { shortcut in
                            Button("\(shortcut.title) (\(shortcut.chordDescription))") {
                                server.testShortcut(shortcut)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(16)
                .background(MacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(MacTheme.border, lineWidth: 1)
                )

                // Telemetry & Rate Diagnostics
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Input Terakhir: \(server.lastInputText)")
                            .font(.caption)
                            .foregroundStyle(MacTheme.textSecondary)

                        Text("Pointer Input: \(server.pointerInputHz) Hz (Target: 60 Hz)")
                            .font(.caption.monospaced())
                            .foregroundStyle(MacTheme.textTertiary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(MacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(20)
        }
    }

    // MARK: - Tab 5: About View

    private var aboutInformationView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer().frame(height: 20)

                EvoPadLogoMark(size: 64)

                Text("EvoPad Mac Helper")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MacTheme.textPrimary)

                Text("Versi 2.0 · Local TLS 1.3 Transport")
                    .font(.caption)
                    .foregroundStyle(MacTheme.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Protokol Jaringan: Bonjour \(PadProtocol.serviceType)")
                    Text("Port Default: \(PadProtocol.port)")
                    Text("ID Server: \(server.serverDeviceId)")
                    Text("Enkripsi: TLS 1.3 Pinned Certificate + Nonce Challenge")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MacTheme.textSecondary)
                .padding(16)
                .background(MacTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(MacTheme.border, lineWidth: 1)
                )

                Text("EvoPad mengubah iPad Anda menjadi wireless trackpad, keyboard, dan touch bar untuk Mac dengan latensi minimal.")
                    .font(.caption)
                    .foregroundStyle(MacTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(20)
        }
    }

    // MARK: - Helper Views & Sheets

    private func gesturePickerRow(_ title: String, symbol: String, direction: PadGestureDirection, value: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: symbol)
                .frame(width: 120, alignment: .leading)
                .font(.system(size: 13, weight: .medium))

            Picker("", selection: value) {
                ForEach(PadSystemAction.allCases) { action in
                    Text("\(action.title) (\(action.shortcutDescription))")
                        .tag(action.rawValue)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button("Tes") {
                server.testGesture(direction)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func pairingApprovalSheet(request: MacServer.PendingPairingApproval) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "ipad.and.arrow.forward")
                .font(.system(size: 42))
                .foregroundStyle(MacTheme.accent)

            Text("Permintaan Pairing iPad")
                .font(.headline)
                .foregroundStyle(MacTheme.textPrimary)

            Text("iPad \"\(request.clientName)\" ingin terhubung dan mengontrol Mac ini melalui saluran terenkripsi.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(MacTheme.textSecondary)
                .padding(.horizontal)

            HStack(spacing: 14) {
                Button("Tolak", role: .cancel) {
                    server.approvePendingPairing(approved: false)
                }
                .buttonStyle(.bordered)

                Button("Izinkan Pairing") {
                    server.approvePendingPairing(approved: true)
                }
                .buttonStyle(.borderedProminent)
                .tint(MacTheme.accent)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(MacTheme.cardBackground)
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
}

// MARK: - EvoPad Logo Mark

struct EvoPadLogoMark: View {
    var size: CGFloat = 36

    var body: some View {
        if let icon = NSImage(named: "AppIcon") {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
                .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 2)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.28)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 37 / 255, green: 115 / 255, blue: 255 / 255),
                                Color(red: 24 / 255, green: 92 / 255, blue: 240 / 255)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.28)
                            .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                    )

                // Double arch ribbon icon
                HStack(spacing: size * 0.08) {
                    RoundedRectangle(cornerRadius: size * 0.12)
                        .strokeBorder(Color.white, lineWidth: size * 0.10)
                        .frame(width: size * 0.30, height: size * 0.48)

                    RoundedRectangle(cornerRadius: size * 0.12)
                        .strokeBorder(Color.white, lineWidth: size * 0.10)
                        .frame(width: size * 0.30, height: size * 0.48)
                }
            }
        }
    }
}

// MARK: - MacBook Vector Illustration

struct MacBookGraphicView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Display Screen Lid
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(red: 25 / 255, green: 28 / 255, blue: 34 / 255))
                    .frame(width: 136, height: 86)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )

                // Bezel Screen with macOS Wave Wallpaper
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 30 / 255, green: 58 / 255, blue: 138 / 255),
                                Color(red: 126 / 255, green: 34 / 255, blue: 206 / 255),
                                Color(red: 219 / 255, green: 39 / 255, blue: 119 / 255),
                                Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 126, height: 76)
                    .overlay(
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 52))
                            path.addCurve(
                                to: CGPoint(x: 126, y: 34),
                                control1: CGPoint(x: 42, y: 14),
                                control2: CGPoint(x: 84, y: 64)
                            )
                            path.addLine(to: CGPoint(x: 126, y: 76))
                            path.addLine(to: CGPoint(x: 0, y: 76))
                            path.closeSubpath()
                        }
                        .fill(Color(red: 192 / 255, green: 132 / 255, blue: 252 / 255).opacity(0.40))
                    )
            }

            // Keyboard Aluminum Base
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 185 / 255, green: 190 / 255, blue: 200 / 255),
                                Color(red: 135 / 255, green: 140 / 255, blue: 150 / 255)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 160, height: 7)

                // Thumb Opening Notch
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 24, height: 2)
            }
        }
    }
}
