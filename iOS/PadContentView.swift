import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum PadNavSection: String, CaseIterable, Identifiable {
    case trackpad = "Trackpad"
    case keyboard = "Keyboard"
    case shortcuts = "Shortcuts"
    case macros = "Macros"
    case control = "Control"
    case workspace = "Workspace"
    case web = "Web"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .trackpad: return "hand.draw.fill"
        case .keyboard: return "keyboard"
        case .shortcuts: return "command"
        case .macros: return "bolt.square"
        case .control: return "slider.horizontal.3"
        case .workspace: return "square.grid.2x2"
        case .web: return "globe"
        }
    }
}

enum PadLayoutMode: String, CaseIterable, Identifiable {
    case fullKeyboard = "Full Keyboard"
    case split = "Split"
    case trackpad = "Trackpad"

    var id: String { rawValue }
}

struct PadContentView: View {
    @StateObject private var connection = PadConnectionManager()
    @StateObject private var macroStore = PadMacroStore.shared
    @StateObject private var workspaceStore = PadWorkspaceStore.shared

    @State private var inputFeedback = "Siap menerima gesture"
    @State private var showingQRScanner = false
    @State private var showingMacroEditor = false
    @State private var editingMacro: PadMacroDefinition?

    // Navigation and Mode (Home = Full Trackpad)
    @State private var activeNavSection: PadNavSection = .trackpad
    @State private var activeLayoutMode: PadLayoutMode = .trackpad
    @State private var isIslandExpanded = false

    // Input Component Visibility (toggled directly via Keyboard & Trackpad tabs)
    @AppStorage("evopad.showKeyboardInMode") private var showKeyboardInMode: Bool = true
    @AppStorage("evopad.showTouchpadInMode") private var showTouchpadInMode: Bool = true

    // 24/7 Continuous Operation & Smart OLED Eco Standby
    @AppStorage("evopad.ecoStandbyEnabled") private var ecoStandbyEnabled: Bool = true
    @State private var isEcoStandbyActive = false
    @State private var lastInteractionAt = Date()
    private let idleCheckTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    // Persistent Modifiers
    @State private var isCmdActive = false
    @State private var isOptActive = false
    @State private var isCtrlActive = false
    @State private var isShiftActive = false

    private var activeModifiers: [PadModifierFlagV2] {
        var mods: [PadModifierFlagV2] = []
        if isCmdActive { mods.append(.cmd) }
        if isOptActive { mods.append(.alt) }
        if isCtrlActive { mods.append(.ctrl) }
        if isShiftActive { mods.append(.shift) }
        return mods
    }

    var body: some View {
        ZStack {
            EvoTheme.background.ignoresSafeArea()

            VStack(spacing: 10) {
                // MARK: - Top Header with EvoPad & Evo Island
                topHeaderBar

                // MARK: - Navigation Bar (Keyboard, Shortcuts, Macros, Control, Workspace)
                navigationTabBar

                // MARK: - Mode Selector (Full Keyboard, Split, Trackpad)
                modeSelectorBar

                // MARK: - Main Content Area
                mainContentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // MARK: - Status & Feedback Strip
                statusFeedbackStrip
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)

            // MARK: - Evo Island Expanded Popover Overlay
            if isIslandExpanded {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                            isIslandExpanded = false
                        }
                    }

                VStack {
                    EvoIslandExpandedCard(
                        connection: connection,
                        isExpanded: $isIslandExpanded,
                        onScanQR: {
                            showingQRScanner = true
                        }
                    )
                    .padding(.top, 56)
                    Spacer()
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                    removal: .opacity
                ))
                .zIndex(100)
            }

            // MARK: - Smart OLED Eco Standby (24/7 Power Saving)
            if isEcoStandbyActive {
                ZStack {
                    Color.black.ignoresSafeArea()

                    VStack(spacing: 12) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.white.opacity(0.22))

                        Text("EvoPad Eco Standby")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.35))

                        HStack(spacing: 6) {
                            Circle()
                                .fill(connection.isAuthenticated ? Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255) : Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255))
                                .frame(width: 6, height: 6)
                            Text(connection.isAuthenticated ? "Mac Terhubung • Mode Hemat Layar" : "Mencari Mac...")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.25))
                        }

                        Text("Sentuh di mana saja untuk mengaktifkan kembali")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.18))
                            .padding(.top, 8)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    recordUserActivity()
                }
                .transition(.opacity)
                .zIndex(150)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
            connection.startDiscovery()
        }
        .onDisappear {
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
        .onReceive(idleCheckTimer) { _ in
            guard ecoStandbyEnabled, !isEcoStandbyActive else { return }
            if Date().timeIntervalSince(lastInteractionAt) > 120 {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isEcoStandbyActive = true
                }
            }
        }
        .onChange(of: connection.isAuthenticated) { _, isAuth in
            if isAuth {
                showingQRScanner = false
            }
        }
        .sheet(isPresented: $showingQRScanner) {
            #if canImport(UIKit)
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
            #endif
        }
        .sheet(isPresented: $showingMacroEditor) {
            PadMacroEditorSheet(existingMacro: editingMacro)
        }
    }

    // MARK: - Top Header Bar with Evo Island

    private var topHeaderBar: some View {
        HStack(spacing: 12) {
            // Brand Mark
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(EvoTheme.accent)
                    .frame(width: 8, height: 18)

                Text("EvoPad")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(EvoTheme.textPrimary)
            }

            Spacer()

            // Evo Island Capsule (Connection Status)
            EvoIslandView(
                connection: connection,
                isExpanded: $isIslandExpanded,
                onScanQR: {
                    showingQRScanner = true
                }
            )

            Spacer()

            // Eco Standby Toggle (24/7 Power Saving)
            Button {
                ecoStandbyEnabled.toggle()
                recordUserActivity()
            } label: {
                Image(systemName: ecoStandbyEnabled ? "leaf.fill" : "leaf")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ecoStandbyEnabled ? Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255) : EvoTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(ecoStandbyEnabled ? Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255).opacity(0.4) : EvoTheme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // Quick QR pairing button shortcut if not paired
            if !connection.isPairedWithMac {
                Button {
                    showingQRScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(EvoTheme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(EvoTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 38)
    }

    private func recordUserActivity() {
        lastInteractionAt = Date()
        if isEcoStandbyActive {
            withAnimation(.easeOut(duration: 0.18)) {
                isEcoStandbyActive = false
            }
        }
    }

    // MARK: - Navigation Tab Bar (7 items with direct on/off toggle for Keyboard & Trackpad)

    private var navigationTabBar: some View {
        HStack(spacing: 6) {
            ForEach(PadNavSection.allCases) { section in
                let isSelected = (activeNavSection == section)
                let isToggledOff = (section == .keyboard && !showKeyboardInMode) || (section == .trackpad && !showTouchpadInMode)

                Button {
                    switchToTab(section)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tabIcon(for: section, isToggledOff: isToggledOff))
                            .font(.system(size: 11, weight: .semibold))
                        Text(tabLabel(for: section, isToggledOff: isToggledOff))
                            .font(.system(size: 12, weight: .medium))

                        if isSelected && (section == .keyboard || section == .trackpad) {
                            Circle()
                                .fill(isToggledOff ? Color.orange : Color.green)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        isSelected
                            ? (isToggledOff ? EvoTheme.panel : EvoTheme.accent)
                            : EvoTheme.panel,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .foregroundStyle(
                        isSelected
                            ? (isToggledOff ? EvoTheme.textSecondary : Color.white)
                            : EvoTheme.textSecondary
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected
                                    ? (isToggledOff ? Color.orange.opacity(0.6) : EvoTheme.borderStrong)
                                    : EvoTheme.border,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if activeNavSection == .macros {
                Button {
                    editingMacro = nil
                    showingMacroEditor = true
                } label: {
                    Label("Tambah", systemImage: "plus")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(EvoTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(EvoTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > abs(dy) {
                        if dx < -25 {
                            switchToNextTab()
                        } else if dx > 25 {
                            switchToPreviousTab()
                        }
                    }
                }
        )
    }

    // MARK: - Mode Selector Bar (Full Keyboard, Split, Trackpad)

    private var modeSelectorBar: some View {
        HStack(spacing: 8) {
            Text("Mode:")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EvoTheme.textTertiary)

            ForEach(PadLayoutMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        activeLayoutMode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 11, weight: activeLayoutMode == mode ? .bold : .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            activeLayoutMode == mode ? EvoTheme.surface : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(activeLayoutMode == mode ? EvoTheme.borderStrong : Color.clear, lineWidth: 1)
                        )
                        .foregroundStyle(activeLayoutMode == mode ? EvoTheme.textPrimary : EvoTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Quick Modifiers Pill Strip (hidden on full keyboard mode unless keyboard is hidden)
            if activeLayoutMode != .fullKeyboard || !showKeyboardInMode {
                HStack(spacing: 4) {
                    modifierPill("⌘", isActive: $isCmdActive)
                    modifierPill("⌥", isActive: $isOptActive)
                    modifierPill("⌃", isActive: $isCtrlActive)
                    modifierPill("⇧", isActive: $isShiftActive)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(EvoTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Main Content Area (per Mode)

    @ViewBuilder
    private var mainContentArea: some View {
        switch activeLayoutMode {
        case .fullKeyboard:
            fullKeyboardModeView
        case .split:
            splitModeView
        case .trackpad:
            trackpadModeView
        }
    }

    // MARK: - Full Keyboard Mode

    private var fullKeyboardModeView: some View {
        VStack(spacing: 6) {
            // Optional Active Navigation Context Panel if not in Keyboard tab
            if activeNavSection != .keyboard {
                activeNavigationPanel
                    .frame(maxHeight: showKeyboardInMode ? 180 : .infinity)
            }

            if showKeyboardInMode {
                // Virtual Touch Bar with dedicated Tab Swipe Zone above it
                touchBarWithDedicatedSwipeZone

                // Full Keyboard taking all remaining height below Touch Bar
                PadVirtualKeyboardView(
                    connection: connection,
                    isCmdActive: $isCmdActive,
                    isOptActive: $isOptActive,
                    isCtrlActive: $isCtrlActive,
                    isShiftActive: $isShiftActive
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if activeNavSection == .keyboard {
                hiddenComponentPlaceholder(
                    title: "Keyboard Dinonaktifkan",
                    subtitle: "Ketuk kembali tab Keyboard di atas untuk mengaktifkan kembali.",
                    actionTitle: "Aktifkan Keyboard",
                    action: { showKeyboardInMode = true }
                )
            }
        }
    }

    // MARK: - Trackpad Mode (Large Trackpad taking maximum space)

    private var trackpadModeView: some View {
        VStack(spacing: 10) {
            // Top Shortcut / Navigation Card (hidden when full Trackpad tab is active)
            if activeNavSection != .trackpad && activeNavSection != .keyboard {
                activeNavigationPanel
                    .frame(maxHeight: showTouchpadInMode ? 230 : .infinity)
            }

            if showTouchpadInMode {
                // Large Trackpad Area
                TrackpadSurface(onCommand: { command in
                    connection.send(command)
                }, onStatus: { message in
                    inputFeedback = message
                })
                .overlay(alignment: .topTrailing) {
                    Text("TRACKPAD")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.24))
                        .padding(14)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("1 Jari: Kursor · 2 Jari: Scroll · 3 Jari: Drag · 4 Jari: Gesture")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.30))
                        .padding(14)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Clean Dark Mouse Buttons
                HStack(spacing: 10) {
                    Button {
                        connection.send(.click(.left))
                    } label: {
                        Label("Left Click", systemImage: "cursorarrow")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(EvoTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(EvoTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        connection.send(.click(.right))
                    } label: {
                        Label("Right Click", systemImage: "cursorarrow.click.2")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(EvoTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(EvoTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            } else if activeNavSection == .trackpad || activeNavSection == .keyboard {
                hiddenComponentPlaceholder(
                    title: "Trackpad Dinonaktifkan",
                    subtitle: "Ketuk kembali tab Trackpad di atas untuk mengaktifkan kembali.",
                    actionTitle: "Aktifkan Trackpad",
                    action: { showTouchpadInMode = true }
                )
            }
        }
    }

    // MARK: - Split Keyboard + Trackpad Mode

    private var splitModeView: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width >= geo.size.height

            if !showKeyboardInMode && !showTouchpadInMode {
                // Keduanya disembunyikan
                VStack(spacing: 10) {
                    if activeNavSection != .trackpad && activeNavSection != .keyboard {
                        activeNavigationPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        hiddenComponentPlaceholder(
                            title: "Keyboard & Trackpad Dinonaktifkan",
                            subtitle: "Ketuk tab Keyboard atau Trackpad di atas untuk mengaktifkan kembali.",
                            actionTitle: "Tampilkan Keduanya",
                            action: {
                                showKeyboardInMode = true
                                showTouchpadInMode = true
                            }
                        )
                    }
                }
            } else if !showKeyboardInMode {
                // Hanya Touchpad muncul di Split mode
                VStack(spacing: 8) {
                    if activeNavSection != .trackpad && activeNavSection != .keyboard {
                        activeNavigationPanel
                            .frame(maxHeight: 180)
                    }
                    splitTrackpadSubView
                }
            } else if !showTouchpadInMode {
                // Hanya Keyboard muncul di Split mode
                VStack(spacing: 8) {
                    if activeNavSection != .trackpad && activeNavSection != .keyboard {
                        activeNavigationPanel
                            .frame(maxHeight: 180)
                    }
                    splitKeyboardSubView
                }
            } else {
                // Keduanya muncul
                if isLandscape {
                    HStack(spacing: 12) {
                        splitKeyboardSubView
                            .frame(width: geo.size.width * 0.58)

                        splitTrackpadSubView
                            .frame(width: geo.size.width * 0.40)
                    }
                } else {
                    VStack(spacing: 10) {
                        TrackpadSurface(onCommand: { command in
                            connection.send(command)
                        }, onStatus: { message in
                            inputFeedback = message
                        })
                        .frame(maxWidth: .infinity, maxHeight: geo.size.height * 0.38)

                        touchBarWithDedicatedSwipeZone

                        PadVirtualKeyboardView(
                            connection: connection,
                            isCmdActive: $isCmdActive,
                            isOptActive: $isOptActive,
                            isCtrlActive: $isCtrlActive,
                            isShiftActive: $isShiftActive
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private var splitKeyboardSubView: some View {
        VStack(spacing: 8) {
            touchBarWithDedicatedSwipeZone

            PadVirtualKeyboardView(
                connection: connection,
                isCmdActive: $isCmdActive,
                isOptActive: $isOptActive,
                isCtrlActive: $isCtrlActive,
                isShiftActive: $isShiftActive
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var splitTrackpadSubView: some View {
        VStack(spacing: 8) {
            TrackpadSurface(onCommand: { command in
                connection.send(command)
            }, onStatus: { message in
                inputFeedback = message
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                Button {
                    connection.send(.click(.left))
                } label: {
                    Text("Left Click")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(EvoTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(EvoTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    connection.send(.click(.right))
                } label: {
                    Text("Right Click")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(EvoTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(EvoTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func hiddenComponentPlaceholder(
        title: String,
        subtitle: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash")
                .font(.system(size: 32))
                .foregroundStyle(EvoTheme.textTertiary)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EvoTheme.textSecondary)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(EvoTheme.textTertiary)
                .multilineTextAlignment(.center)

            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(EvoTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EvoTheme.panel.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(EvoTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Active Navigation Panel (Shortcuts, Macros, Control, Workspace)

    @ViewBuilder
    private var activeNavigationPanel: some View {
        switch activeNavSection {
        case .trackpad:
            EmptyView()

        case .keyboard:
            // Quick Touch Bar Strip with dedicated Tab Swipe Zone when Keyboard navigation is active
            touchBarWithDedicatedSwipeZone

        case .shortcuts:
            PadShortcutsCatalogView(
                connection: connection,
                onActionFeedback: { message in
                    inputFeedback = message
                }
            )

        case .macros:
            PadMacrosCatalogView(
                connection: connection,
                macroStore: macroStore,
                showingEditor: $showingMacroEditor,
                editingMacro: $editingMacro,
                onActionFeedback: { message in
                    inputFeedback = message
                }
            )

        case .control:
            PadControlCenterView(
                connection: connection,
                onActionFeedback: { message in
                    inputFeedback = message
                }
            )

        case .workspace:
            PadControlPanelView(
                connection: connection,
                workspaceStore: workspaceStore,
                macroStore: macroStore,
                onActionFeedback: { message in
                    inputFeedback = message
                }
            )

        case .web:
            PadPopularWebsitesView(connection: connection)
        }
    }

    // MARK: - Status & Feedback Strip

    // MARK: - Status & Feedback Strip (with Swipe Navigation Cue)

    private var statusFeedbackStrip: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.compact.left")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(EvoTheme.textTertiary)

                Text(inputFeedback)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(EvoTheme.textSecondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("evopad.inputFeedback")

                Image(systemName: "chevron.compact.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(EvoTheme.textTertiary)
            }

            Spacer()

            Text("Mac: \(connection.macFeedback)")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(EvoTheme.textTertiary)
                .lineLimit(1)
                .accessibilityIdentifier("evopad.macFeedback")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > abs(dy) {
                        if dx < -25 {
                            switchToNextTab()
                        } else if dx > 25 {
                            switchToPreviousTab()
                        }
                    }
                }
        )
    }

    // MARK: - Dedicated Tab Swipe Zone (Protects TouchBar from Accidental Gestures)

    private var touchBarTabSwipeZone: some View {
        HStack(spacing: 8) {
            // Previous tab shortcut cue
            if let prevTab = previousTab {
                Button {
                    switchToPreviousTab()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))
                        Image(systemName: prevTab.icon)
                            .font(.system(size: 9))
                        Text(prevTab.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(EvoTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(EvoTheme.surface, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(EvoTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 28)
            }

            Spacer()

            // Center gesture strip with indicator dots
            HStack(spacing: 6) {
                Image(systemName: "chevron.compact.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(EvoTheme.textTertiary)

                HStack(spacing: 6) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(EvoTheme.accent)

                    Text("Swipe Tab")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(EvoTheme.accent)

                    Text("•")
                        .font(.system(size: 9))
                        .foregroundStyle(EvoTheme.textTertiary)

                    HStack(spacing: 4) {
                        ForEach(PadNavSection.allCases) { sec in
                            Circle()
                                .fill(sec == activeNavSection ? EvoTheme.accent : EvoTheme.borderStrong)
                                .frame(width: sec == activeNavSection ? 6 : 4, height: sec == activeNavSection ? 6 : 4)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(EvoTheme.surface, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(EvoTheme.accent.opacity(0.35), lineWidth: 1)
                )

                Image(systemName: "chevron.compact.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(EvoTheme.textTertiary)
            }

            Spacer()

            // Next tab shortcut cue
            if let nextTab = nextTab {
                Button {
                    switchToNextTab()
                } label: {
                    HStack(spacing: 4) {
                        Text(nextTab.rawValue)
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: nextTab.icon)
                            .font(.system(size: 9))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(EvoTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(EvoTheme.surface, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(EvoTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 28)
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 8)
        .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(EvoTheme.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > abs(dy) {
                        if dx < -20 {
                            switchToNextTab()
                        } else if dx > 20 {
                            switchToPreviousTab()
                        }
                    }
                }
        )
    }

    private var touchBarWithDedicatedSwipeZone: some View {
        VStack(spacing: 4) {
            // Dedicated swipe zone that keeps touchbar buttons intact
            touchBarTabSwipeZone

            EvoTouchBarView(
                connection: connection,
                activeModifiers: activeModifiers,
                onTriggerShortcut: triggerShortcut,
                onOpenWebShortcuts: {
                    switchToTab(.web)
                }
            )
        }
    }

    // MARK: - Tab Navigation Helpers

    private var currentTabIndex: Int {
        PadNavSection.allCases.firstIndex(of: activeNavSection) ?? 0
    }

    private var previousTab: PadNavSection? {
        let idx = currentTabIndex
        guard idx > 0 else { return nil }
        return PadNavSection.allCases[idx - 1]
    }

    private var nextTab: PadNavSection? {
        let idx = currentTabIndex
        guard idx < PadNavSection.allCases.count - 1 else { return nil }
        return PadNavSection.allCases[idx + 1]
    }

    private func switchToNextTab() {
        if let next = nextTab {
            switchToTab(next)
        }
    }

    private func switchToPreviousTab() {
        if let prev = previousTab {
            switchToTab(prev)
        }
    }

    private func tabIcon(for section: PadNavSection, isToggledOff: Bool) -> String {
        if isToggledOff {
            switch section {
            case .keyboard: return "keyboard.badge.eye.slash"
            case .trackpad: return "hand.draw"
            default: return section.icon
            }
        }
        return section.icon
    }

    private func tabLabel(for section: PadNavSection, isToggledOff: Bool) -> String {
        if isToggledOff {
            switch section {
            case .keyboard: return "Keyboard (Off)"
            case .trackpad: return "Trackpad (Off)"
            default: return section.rawValue
            }
        }
        return section.rawValue
    }

    private func switchToTab(_ section: PadNavSection) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        withAnimation(.easeInOut(duration: 0.18)) {
            if activeNavSection == section {
                // Tapped again while already active: toggle on/off!
                if section == .keyboard {
                    showKeyboardInMode.toggle()
                    inputFeedback = showKeyboardInMode ? "Keyboard aktif" : "Keyboard dinonaktifkan"
                    return
                } else if section == .trackpad {
                    showTouchpadInMode.toggle()
                    inputFeedback = showTouchpadInMode ? "Trackpad aktif" : "Trackpad dinonaktifkan"
                    return
                }
            } else {
                activeNavSection = section
                if section == .keyboard {
                    activeLayoutMode = .fullKeyboard
                    showKeyboardInMode = true
                } else if section == .trackpad {
                    activeLayoutMode = .trackpad
                    showTouchpadInMode = true
                }
            }
        }
        inputFeedback = "Tab: \(section.rawValue)"
    }

    // MARK: - Helper Views

    private func modifierPill(_ label: String, isActive: Binding<Bool>) -> some View {
        Button {
            isActive.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive.wrappedValue ? EvoTheme.accent : EvoTheme.keySurface, in: Capsule())
                .foregroundStyle(isActive.wrappedValue ? Color.white : EvoTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(!connection.isAuthenticated)
    }

    private func triggerShortcut(_ shortcut: PadStandardShortcut) {
        let activeMods = activeModifiers
        if activeMods.isEmpty {
            connection.sendShortcut(shortcut)
        } else {
            var merged = Set(shortcut.modifiers)
            for mod in activeMods {
                merged.insert(mod)
            }
            connection.sendCustomShortcut(keyCode: shortcut.keyCode, modifiers: Array(merged))
        }
    }
}

// MARK: - M7 Shortcuts Catalog View (Unified UI matching Web & Workspace)

struct PadShortcutCatalogItem: Identifiable {
    let id: String
    let title: String
    let hotkeyDisplay: String
    let icon: String
    let description: String
    let standardShortcut: PadStandardShortcut?
    let customKeyCode: UInt16?
    let customModifiers: [PadModifierFlagV2]

    init(
        id: String = UUID().uuidString,
        title: String,
        hotkeyDisplay: String,
        icon: String,
        description: String,
        standardShortcut: PadStandardShortcut? = nil,
        customKeyCode: UInt16? = nil,
        customModifiers: [PadModifierFlagV2] = []
    ) {
        self.id = id
        self.title = title
        self.hotkeyDisplay = hotkeyDisplay
        self.icon = icon
        self.description = description
        self.standardShortcut = standardShortcut
        self.customKeyCode = customKeyCode
        self.customModifiers = customModifiers
    }
}

struct PadShortcutCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let themeColor: Color
    let subtitle: String
    let description: String
    let shortcuts: [PadShortcutCatalogItem]
}

enum PadShortcutsCatalogData {
    static let subcategories: [PadShortcutCategory] = [
        PadShortcutCategory(
            id: "cat.clipboard",
            name: "Clipboard & Edit",
            icon: "doc.on.clipboard.fill",
            themeColor: Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255),
            subtitle: "Manipulasi Teks & Dokumen",
            description: "Perintah copy, paste, undo, redo, dan seleksi konten",
            shortcuts: [
                PadShortcutCatalogItem(title: "Salin (Copy)", hotkeyDisplay: "⌘ C", icon: "doc.on.doc", description: "Salin teks atau file terpilih", standardShortcut: .copy),
                PadShortcutCatalogItem(title: "Tempel (Paste)", hotkeyDisplay: "⌘ V", icon: "doc.on.clipboard", description: "Tempel isi clipboard ke posisi kursor", standardShortcut: .paste),
                PadShortcutCatalogItem(title: "Potong (Cut)", hotkeyDisplay: "⌘ X", icon: "scissors", description: "Potong teks atau item ke clipboard", standardShortcut: .cut),
                PadShortcutCatalogItem(title: "Undo", hotkeyDisplay: "⌘ Z", icon: "arrow.uturn.backward", description: "Batalkan aksi terakhir", standardShortcut: .undo),
                PadShortcutCatalogItem(title: "Redo", hotkeyDisplay: "⌘ ⇧ Z", icon: "arrow.uturn.forward", description: "Ulangi kembali aksi yang dibatalkan", standardShortcut: .redo),
                PadShortcutCatalogItem(title: "Pilih Semua", hotkeyDisplay: "⌘ A", icon: "selection.pin.in.out", description: "Sorot seluruh konten dalam dokumen", standardShortcut: .selectAll),
                PadShortcutCatalogItem(title: "Cari (Find)", hotkeyDisplay: "⌘ F", icon: "magnifyingglass", description: "Buka bilah pencarian kata pada aplikasi", customKeyCode: 3, customModifiers: [.cmd]),
                PadShortcutCatalogItem(title: "Cari & Ganti", hotkeyDisplay: "⌘ ⌥ F", icon: "arrow.triangle.2.circlepath", description: "Temukan teks dan ganti dengan kata baru", customKeyCode: 3, customModifiers: [.cmd, .alt])
            ]
        ),
        PadShortcutCategory(
            id: "cat.navigation",
            name: "Navigasi & Jendela",
            icon: "macwindow",
            themeColor: Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255),
            subtitle: "Manajemen Jendela & Aplikasi",
            description: "Pindah antar app, tutup tab, minimalkan jendela",
            shortcuts: [
                PadShortcutCatalogItem(title: "Beralih App", hotkeyDisplay: "⌘ Tab", icon: "app.badge", description: "Pindah cepat ke aplikasi lain yang berjalan", standardShortcut: .commandTab),
                PadShortcutCatalogItem(title: "Spotlight Search", hotkeyDisplay: "⌘ Space", icon: "magnifyingglass", description: "Buka pencarian global macOS", standardShortcut: .spotlight),
                PadShortcutCatalogItem(title: "Tutup Jendela", hotkeyDisplay: "⌘ W", icon: "xmark.circle.fill", description: "Tutup jendela atau tab aktif saat ini", customKeyCode: 13, customModifiers: [.cmd]),
                PadShortcutCatalogItem(title: "Keluar App (Quit)", hotkeyDisplay: "⌘ Q", icon: "power", description: "Hentikan aplikasi yang sedang aktif", customKeyCode: 12, customModifiers: [.cmd]),
                PadShortcutCatalogItem(title: "Sembunyikan App", hotkeyDisplay: "⌘ H", icon: "eye.slash.fill", description: "Sembunyikan semua jendela app yang aktif", customKeyCode: 4, customModifiers: [.cmd]),
                PadShortcutCatalogItem(title: "Minimalkan Jendela", hotkeyDisplay: "⌘ M", icon: "arrow.down.right.and.arrow.up.left", description: "Kecilkan jendela ke dock macOS", customKeyCode: 46, customModifiers: [.cmd]),
                PadShortcutCatalogItem(title: "Layar Penuh", hotkeyDisplay: "⌃ ⌘ F", icon: "arrow.up.left.and.arrow.down.right", description: "Beralih ke tampilan layar penuh", customKeyCode: 3, customModifiers: [.ctrl, .cmd]),
                PadShortcutCatalogItem(title: "Siklus Jendela App", hotkeyDisplay: "⌘ `", icon: "square.stack.3d.down.right", description: "Pindah antar jendela dari app yang sama", customKeyCode: 50, customModifiers: [.cmd])
            ]
        ),
        PadShortcutCategory(
            id: "cat.screenshot",
            name: "Screenshot & Rekam",
            icon: "camera.viewfinder",
            themeColor: Color(red: 20 / 255, green: 184 / 255, blue: 166 / 255),
            subtitle: "Tangkapan & Rekaman Layar",
            description: "Ambil gambar layar penuh, area persegi, atau jendela",
            shortcuts: [
                PadShortcutCatalogItem(title: "Layar Penuh", hotkeyDisplay: "⌘ ⇧ 3", icon: "display", description: "Simpan tangkapan seluruh layar sebagai file", customKeyCode: 20, customModifiers: [.cmd, .shift]),
                PadShortcutCatalogItem(title: "Pilih Area (Kotak)", hotkeyDisplay: "⌘ ⇧ 4", icon: "crop", description: "Tarik kursor untuk memotong area layar", standardShortcut: .screenshot),
                PadShortcutCatalogItem(title: "Menu Rekam Layar", hotkeyDisplay: "⌘ ⇧ 5", icon: "record.circle", description: "Buka utilitas screenshot & rekam video", customKeyCode: 23, customModifiers: [.cmd, .shift]),
                PadShortcutCatalogItem(title: "Salin Area Layar", hotkeyDisplay: "⌃ ⌘ ⇧ 4", icon: "doc.on.clipboard.fill", description: "Ambil area langsung ke clipboard tanpa simpan file", customKeyCode: 21, customModifiers: [.ctrl, .cmd, .shift])
            ]
        ),
        PadShortcutCategory(
            id: "cat.system",
            name: "Sistem & Finder",
            icon: "gearshape.fill",
            themeColor: Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255),
            subtitle: "Kontrol Lingkungan macOS",
            description: "Mission Control, Lock Screen, Force Quit, Preferences",
            shortcuts: [
                PadShortcutCatalogItem(title: "Mission Control", hotkeyDisplay: "⌃ ↑", icon: "rectangle.3.group", description: "Tampilkan semua jendela terbuka dalam satu layar", standardShortcut: .missionControl),
                PadShortcutCatalogItem(title: "Kunci Layar (Lock)", hotkeyDisplay: "⌃ ⌘ Q", icon: "lock.fill", description: "Kunci Mac seketika demi privasi", standardShortcut: .lockScreen),
                PadShortcutCatalogItem(title: "Paksa Berhenti (Force Quit)", hotkeyDisplay: "⌘ ⌥ Esc", icon: "exclamationmark.octagon.fill", description: "Buka dialog force quit untuk mematikan app", customKeyCode: 53, customModifiers: [.cmd, .alt]),
                PadShortcutCatalogItem(title: "Pengaturan (Settings)", hotkeyDisplay: "⌘ ,", icon: "gearshape", description: "Buka jendela preferensi atau pengaturan app", customKeyCode: 43, customModifiers: [.cmd]),
                PadShortcutCatalogItem(title: "Tampilkan/Sembunyikan Dock", hotkeyDisplay: "⌘ ⌥ D", icon: "dock.rectangle", description: "Toggle visibilitas dock di tepi layar", customKeyCode: 2, customModifiers: [.cmd, .alt]),
                PadShortcutCatalogItem(title: "Finder Jendela Baru", hotkeyDisplay: "⌘ N", icon: "folder.fill", description: "Buka tab atau jendela baru file manager", customKeyCode: 45, customModifiers: [.cmd])
            ]
        ),
        PadShortcutCategory(
            id: "cat.developer",
            name: "Developer & Terminal",
            icon: "chevron.left.forwardslash.chevron.right",
            themeColor: Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255),
            subtitle: "Alat Koding & Command Line",
            description: "Perintah praktis Xcode, VS Code, dan Terminal",
            shortcuts: [
                PadShortcutCatalogItem(title: "Terminal Baru", hotkeyDisplay: "⌘ T", icon: "terminal.fill", description: "Buka tab terminal baru", customKeyCode: 17, customModifiers: [.cmd]),
                PadShortcutCatalogItem(title: "Bersihkan Terminal (Clear)", hotkeyDisplay: "⌘ K", icon: "trash.fill", description: "Hapus riwayat scroll terminal aktif", customKeyCode: 40, customModifiers: [.cmd]),
                PadShortcutCatalogItem(title: "Hentikan Proses (SIGINT)", hotkeyDisplay: "⌃ C", icon: "xmark.octagon", description: "Kirim sinyal stop ke proses di terminal", customKeyCode: 8, customModifiers: [.ctrl]),
                PadShortcutCatalogItem(title: "Build Proyek", hotkeyDisplay: "⌘ B", icon: "hammer.fill", description: "Kompilasi proyek di IDE", customKeyCode: 11, customModifiers: [.cmd]),
                PadShortcutCatalogItem(title: "Jalankan Proyek (Run)", hotkeyDisplay: "⌘ R", icon: "play.fill", description: "Jalankan aplikasi di simulator/target", customKeyCode: 15, customModifiers: [.cmd]),
                PadShortcutCatalogItem(title: "Komentar Kode (Toggle)", hotkeyDisplay: "⌘ /", icon: "text.quote", description: "Beri atau hapus tanda komentar pada baris kode", customKeyCode: 44, customModifiers: [.cmd])
            ]
        )
    ]

    static var categories: [PadShortcutCategory] {
        var allList: [PadShortcutCatalogItem] = []
        for cat in subcategories {
            allList.append(contentsOf: cat.shortcuts)
        }
        let allCategory = PadShortcutCategory(
            id: "cat.all",
            name: "Semua",
            icon: "square.grid.2x2.fill",
            themeColor: Color.indigo,
            subtitle: "Katalog Lengkap macOS",
            description: "Daftar shortcut esensial macOS untuk produktivitas maksimal",
            shortcuts: allList
        )
        return [allCategory] + subcategories
    }
}

struct PadShortcutsCatalogView: View {
    @ObservedObject var connection: PadConnectionManager
    var onActionFeedback: ((String) -> Void)? = nil

    @State private var selectedCategoryId: String = "cat.all"
    @State private var searchText: String = ""
    @State private var feedbackMessage: String?

    private var categories: [PadShortcutCategory] {
        PadShortcutsCatalogData.categories
    }

    private var selectedCategory: PadShortcutCategory {
        categories.first(where: { $0.id == selectedCategoryId }) ?? categories[0]
    }

    private var filteredShortcuts: [PadShortcutCatalogItem] {
        let baseList = selectedCategory.shortcuts
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return baseList
        }
        let query = searchText.lowercased()
        return baseList.filter {
            $0.title.lowercased().contains(query) ||
            $0.hotkeyDisplay.lowercased().contains(query) ||
            $0.description.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // 1. Horizontal Category Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { cat in
                        let isSelected = (cat.id == selectedCategory.id)
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedCategoryId = cat.id
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.white : cat.themeColor)

                                Text(cat.name)
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? Color.white : EvoTheme.textPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? cat.themeColor : EvoTheme.panel,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(isSelected ? Color.white.opacity(0.25) : EvoTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }

            // 2. Info Banner / Header Card
            HStack(spacing: 12) {
                Image(systemName: selectedCategory.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(selectedCategory.themeColor)
                    .frame(width: 38, height: 38)
                    .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(selectedCategory.themeColor.opacity(0.35), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(selectedCategory.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(EvoTheme.textPrimary)

                        Text("•")
                            .foregroundStyle(EvoTheme.textTertiary)

                        Text("\(filteredShortcuts.count) shortcut")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(EvoTheme.textSecondary)
                    }

                    Text(selectedCategory.description)
                        .font(.system(size: 11))
                        .foregroundStyle(EvoTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Subtitle Badge
                Text(selectedCategory.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selectedCategory.themeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(selectedCategory.themeColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selectedCategory.themeColor.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(EvoTheme.border, lineWidth: 1)
            )

            // 3. Quick Search Filter
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(EvoTheme.textTertiary)

                TextField("Cari shortcut (misal: Copy, Screenshot, Tab)...", text: $searchText)
                    .font(.system(size: 12))
                    .foregroundStyle(EvoTheme.textPrimary)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(EvoTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(EvoTheme.border, lineWidth: 1)
            )

            // 4. Shortcuts Grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                    ForEach(filteredShortcuts) { item in
                        Button {
                            executeShortcut(item)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(selectedCategory.themeColor)
                                    .frame(width: 28, height: 28)
                                    .background(EvoTheme.surface, in: RoundedRectangle(cornerRadius: 7))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(EvoTheme.textPrimary)
                                        .lineLimit(1)

                                    Text(item.description)
                                        .font(.system(size: 10))
                                        .foregroundStyle(EvoTheme.textSecondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)

                                Text(item.hotkeyDisplay)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(EvoTheme.textPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(EvoTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(EvoTheme.borderStrong, lineWidth: 1)
                                    )
                            }
                            .padding(8)
                            .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(EvoTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!connection.isAuthenticated)
                    }
                }
                .padding(.vertical, 2)
            }

            // 5. Feedback Banner
            if let feedback = feedbackMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255))
                    Text(feedback)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EvoTheme.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(EvoTheme.surface, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(EvoTheme.borderStrong, lineWidth: 1)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(10)
        .background(EvoTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(EvoTheme.border, lineWidth: 1)
        )
    }

    private func executeShortcut(_ item: PadShortcutCatalogItem) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        if let std = item.standardShortcut {
            connection.sendShortcut(std)
            showFeedback("Shortcut: \(item.title) (\(item.hotkeyDisplay))")
            onActionFeedback?("Shortcut: \(item.title)")
        } else if let code = item.customKeyCode {
            connection.sendCustomShortcut(keyCode: code, modifiers: item.customModifiers)
            showFeedback("Shortcut: \(item.title) (\(item.hotkeyDisplay))")
            onActionFeedback?("Shortcut: \(item.title)")
        }
    }

    private func showFeedback(_ text: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            feedbackMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if feedbackMessage == text {
                    feedbackMessage = nil
                }
            }
        }
    }
}

// MARK: - M7 Macros Catalog View (Unified UI matching Web & Workspace)

struct PadMacroCategoryItem: Identifiable {
    let id: String
    let name: String
    let icon: String
    let themeColor: Color
    let description: String
}

struct PadMacrosCatalogView: View {
    @ObservedObject var connection: PadConnectionManager
    @ObservedObject var macroStore: PadMacroStore
    @Binding var showingEditor: Bool
    @Binding var editingMacro: PadMacroDefinition?
    var onActionFeedback: ((String) -> Void)? = nil

    @State private var selectedCategoryId: String = "cat.all"
    @State private var searchText: String = ""
    @State private var feedbackMessage: String?

    private static let categories: [PadMacroCategoryItem] = [
        PadMacroCategoryItem(id: "cat.all", name: "Semua", icon: "bolt.fill", themeColor: Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255), description: "Semua otomasi macro tersimpan"),
        PadMacroCategoryItem(id: "cat.presets", name: "Preset Bawaan", icon: "star.fill", themeColor: Color(red: 234 / 255, green: 179 / 255, blue: 8 / 255), description: "Otomasi standar siap pakai"),
        PadMacroCategoryItem(id: "cat.custom", name: "Macro Kustom", icon: "slider.horizontal.2.square", themeColor: Color(red: 6 / 255, green: 182 / 255, blue: 212 / 255), description: "Macro yang Anda buat sendiri"),
        PadMacroCategoryItem(id: "cat.web", name: "Navigasi Web", icon: "globe", themeColor: Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255), description: "Otomasi browser dan link cepat")
    ]

    private var selectedCategory: PadMacroCategoryItem {
        Self.categories.first(where: { $0.id == selectedCategoryId }) ?? Self.categories[0]
    }

    private var filteredMacros: [PadMacroDefinition] {
        let base: [PadMacroDefinition]
        switch selectedCategoryId {
        case "cat.presets":
            base = macroStore.macros.filter { $0.id.hasPrefix("preset.") }
        case "cat.custom":
            base = macroStore.macros.filter { !$0.id.hasPrefix("preset.") }
        case "cat.web":
            base = macroStore.macros.filter { $0.name.lowercased().contains("youtube") || $0.name.lowercased().contains("google") || $0.name.lowercased().contains("web") || $0.name.lowercased().contains("buka") }
        default:
            base = macroStore.macros
        }

        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return base
        }
        let query = searchText.lowercased()
        return base.filter {
            $0.name.lowercased().contains(query) ||
            $0.steps.contains(where: { step in
                (step.text?.lowercased().contains(query) ?? false) ||
                step.action.lowercased().contains(query)
            })
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // 1. Horizontal Category Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.categories) { cat in
                        let isSelected = (cat.id == selectedCategory.id)
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedCategoryId = cat.id
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.white : cat.themeColor)

                                Text(cat.name)
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? Color.white : EvoTheme.textPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? cat.themeColor : EvoTheme.panel,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(isSelected ? Color.white.opacity(0.25) : EvoTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }

            // 2. Info Banner & Add Macro Button
            HStack(spacing: 12) {
                Image(systemName: selectedCategory.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(selectedCategory.themeColor)
                    .frame(width: 38, height: 38)
                    .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(selectedCategory.themeColor.opacity(0.35), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(selectedCategory.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(EvoTheme.textPrimary)

                        Text("•")
                            .foregroundStyle(EvoTheme.textTertiary)

                        Text("\(filteredMacros.count) macro")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(EvoTheme.textSecondary)
                    }

                    Text(selectedCategory.description)
                        .font(.system(size: 11))
                        .foregroundStyle(EvoTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Add Macro Button
                Button {
                    editingMacro = nil
                    showingEditor = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Buat Macro")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(selectedCategory.themeColor, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(EvoTheme.border, lineWidth: 1)
            )

            // 3. Quick Search Filter
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(EvoTheme.textTertiary)

                TextField("Cari macro berdasarkan nama atau langkah...", text: $searchText)
                    .font(.system(size: 12))
                    .foregroundStyle(EvoTheme.textPrimary)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(EvoTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(EvoTheme.border, lineWidth: 1)
            )

            // 4. Macro Grid Cards
            ScrollView {
                if filteredMacros.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bolt.slash.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(EvoTheme.textTertiary)
                        Text("Tidak ada macro yang cocok")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(EvoTheme.textSecondary)
                        Button("Buat Macro Baru") {
                            editingMacro = nil
                            showingEditor = true
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(EvoTheme.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                        ForEach(filteredMacros) { macro in
                            Button {
                                runMacro(macro)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: macro.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(selectedCategory.themeColor)
                                        .frame(width: 28, height: 28)
                                        .background(EvoTheme.surface, in: RoundedRectangle(cornerRadius: 7))

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(macro.name)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(EvoTheme.textPrimary)
                                            .lineLimit(1)

                                        Text(stepPreviewText(macro))
                                            .font(.system(size: 10))
                                            .foregroundStyle(EvoTheme.textSecondary)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 4)

                                    Text("\(macro.steps.count) STEPS")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(EvoTheme.textPrimary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(EvoTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(EvoTheme.borderStrong, lineWidth: 1)
                                        )
                                }
                                .padding(8)
                                .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9)
                                        .strokeBorder(EvoTheme.border, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!connection.isAuthenticated)
                            .contextMenu {
                                Button {
                                    runMacro(macro)
                                } label: {
                                    Label("Jalankan Macro", systemImage: "play.fill")
                                }
                                Button {
                                    editingMacro = macro
                                    showingEditor = true
                                } label: {
                                    Label("Edit Macro", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    macroStore.deleteMacro(id: macro.id)
                                    showFeedback("Macro '\(macro.name)' dihapus")
                                } label: {
                                    Label("Hapus Macro", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // 5. Feedback Banner
            if let feedback = feedbackMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255))
                    Text(feedback)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EvoTheme.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(EvoTheme.surface, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(EvoTheme.borderStrong, lineWidth: 1)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(10)
        .background(EvoTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(EvoTheme.border, lineWidth: 1)
        )
    }

    private func stepPreviewText(_ macro: PadMacroDefinition) -> String {
        let actions = macro.steps.prefix(3).map { $0.action }
        return actions.joined(separator: " → ")
    }

    private func runMacro(_ macro: PadMacroDefinition) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        connection.sendMacro(macroId: macro.id, steps: macro.steps)
        showFeedback("Menjalankan: \(macro.name)")
        onActionFeedback?("Macro: \(macro.name)")
    }

    private func showFeedback(_ text: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            feedbackMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if feedbackMessage == text {
                    feedbackMessage = nil
                }
            }
        }
    }
}

// MARK: - M7 Control Center View (Unified UI matching Web & Workspace)

struct PadControlItemModel: Identifiable {
    let id: String
    let title: String
    let badgeDisplay: String
    let icon: String
    let description: String
    let mediaKey: PadMediaControlKey?
    let systemAction: PadSystemControlAction?
    let targetApp: String?
    let customKeyCode: UInt16?
    let customModifiers: [PadModifierFlagV2]

    init(
        id: String = UUID().uuidString,
        title: String,
        badgeDisplay: String,
        icon: String,
        description: String,
        mediaKey: PadMediaControlKey? = nil,
        systemAction: PadSystemControlAction? = nil,
        targetApp: String? = nil,
        customKeyCode: UInt16? = nil,
        customModifiers: [PadModifierFlagV2] = []
    ) {
        self.id = id
        self.title = title
        self.badgeDisplay = badgeDisplay
        self.icon = icon
        self.description = description
        self.mediaKey = mediaKey
        self.systemAction = systemAction
        self.targetApp = targetApp
        self.customKeyCode = customKeyCode
        self.customModifiers = customModifiers
    }
}

struct PadControlCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let themeColor: Color
    let subtitle: String
    let description: String
    let items: [PadControlItemModel]
}

enum PadControlCenterData {
    static let subcategories: [PadControlCategory] = [
        PadControlCategory(
            id: "cat.media",
            name: "Media & Audio",
            icon: "waveform",
            themeColor: Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255),
            subtitle: "Pemutar Musik & Volume",
            description: "Kendali playback lagu, podcast, video, dan output volume",
            items: [
                PadControlItemModel(title: "Play / Pause", badgeDisplay: "MEDIA", icon: "playpause.fill", description: "Putar atau jeda media yang sedang aktif", mediaKey: .playPause),
                PadControlItemModel(title: "Lagu Berikutnya", badgeDisplay: "NEXT", icon: "forward.fill", description: "Lompati ke trek atau bab berikutnya", mediaKey: .nextTrack),
                PadControlItemModel(title: "Lagu Sebelumnya", badgeDisplay: "PREV", icon: "backward.fill", description: "Kembali ke lagu sebelumnya", mediaKey: .previousTrack),
                PadControlItemModel(title: "Volume Naik", badgeDisplay: "VOL +", icon: "speaker.wave.3.fill", description: "Tingkatkan intensitas volume suara", mediaKey: .volumeUp),
                PadControlItemModel(title: "Volume Turun", badgeDisplay: "VOL -", icon: "speaker.wave.1.fill", description: "Kurangi tingkat volume suara", mediaKey: .volumeDown),
                PadControlItemModel(title: "Senyapkan Audio", badgeDisplay: "MUTE", icon: "speaker.slash.fill", description: "Matikan suara audio seketika", mediaKey: .mute)
            ]
        ),
        PadControlCategory(
            id: "cat.system",
            name: "Sistem & Daya",
            icon: "desktopcomputer",
            themeColor: Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255),
            subtitle: "Keamanan & Pengoperasian",
            description: "Kunci layar, screenshot, sleep, dan navigasi global",
            items: [
                PadControlItemModel(title: "Tangkapan Layar", badgeDisplay: "CAPTURE", icon: "camera.viewfinder", description: "Ambil gambar tangkapan layar instan", systemAction: .screenshot),
                PadControlItemModel(title: "Kunci Layar (Lock)", badgeDisplay: "LOCK", icon: "lock.fill", description: "Kunci layar Mac seketika demi keamanan", systemAction: .lockScreen),
                PadControlItemModel(title: "Mode Tidur (Sleep)", badgeDisplay: "SLEEP", icon: "moon.fill", description: "Masukkan Mac ke dalam kondisi sleep hemat daya", systemAction: .sleep),
                PadControlItemModel(title: "Mission Control", badgeDisplay: "⌃ ↑", icon: "rectangle.3.group", description: "Buka ringkasan semua jendela desktop", customKeyCode: 126, customModifiers: [.ctrl, .fn]),
                PadControlItemModel(title: "App Exposé", badgeDisplay: "⌃ ↓", icon: "rectangle.bottomhalf.filled", description: "Tampilkan semua jendela dari app saat ini", customKeyCode: 125, customModifiers: [.ctrl, .fn]),
                PadControlItemModel(title: "Spotlight Search", badgeDisplay: "⌘ Space", icon: "magnifyingglass", description: "Buka input pencarian berkas dan aplikasi", customKeyCode: 49, customModifiers: [.cmd])
            ]
        ),
        PadControlCategory(
            id: "cat.windows",
            name: "Jendela & Layar",
            icon: "macwindow.on.rectangle",
            themeColor: Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255),
            subtitle: "Desktop & Spaces",
            description: "Navigasi ruang kerja desktop dan mode tampilan jendela",
            items: [
                PadControlItemModel(title: "Desktop Berikutnya", badgeDisplay: "⌃ →", icon: "arrow.right.to.line.compact", description: "Pindah ke ruang desktop sebelah kanan", customKeyCode: 124, customModifiers: [.ctrl, .fn]),
                PadControlItemModel(title: "Desktop Sebelumnya", badgeDisplay: "⌃ ←", icon: "arrow.left.to.line.compact", description: "Pindah ke ruang desktop sebelah kiri", customKeyCode: 123, customModifiers: [.ctrl, .fn]),
                PadControlItemModel(title: "Layar Penuh", badgeDisplay: "⌃ ⌘ F", icon: "arrow.up.left.and.arrow.down.right", description: "Ubah jendela menjadi mode layar penuh", customKeyCode: 3, customModifiers: [.ctrl, .cmd]),
                PadControlItemModel(title: "Sembunyikan Lainnya", badgeDisplay: "⌘ ⌥ H", icon: "eye.slash", description: "Fokus ke app ini dan sembunyikan app lain", customKeyCode: 4, customModifiers: [.cmd, .alt]),
                PadControlItemModel(title: "Tutup Tab / Jendela", badgeDisplay: "⌘ W", icon: "xmark.square.fill", description: "Tutup tab aktif tanpa keluar aplikasi", customKeyCode: 13, customModifiers: [.cmd]),
                PadControlItemModel(title: "Paksa Berhenti (Force Quit)", badgeDisplay: "⌘ ⌥ Esc", icon: "exclamationmark.octagon.fill", description: "Buka menu force quit app", customKeyCode: 53, customModifiers: [.cmd, .alt])
            ]
        ),
        PadControlCategory(
            id: "cat.apps",
            name: "Aplikasi Cepat",
            icon: "app.badge.fill",
            themeColor: Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255),
            subtitle: "Peluncur Utilitas Mac",
            description: "Buka aplikasi utama Mac secara instan dengan satu ketukan",
            items: [
                PadControlItemModel(title: "Finder", badgeDisplay: "APP", icon: "folder.fill", description: "Buka pengelola berkas macOS Finder", systemAction: .launchApp, targetApp: "com.apple.finder"),
                PadControlItemModel(title: "Terminal", badgeDisplay: "APP", icon: "terminal.fill", description: "Luncurkan baris perintah Terminal", systemAction: .launchApp, targetApp: "com.apple.Terminal"),
                PadControlItemModel(title: "Safari / Browser", badgeDisplay: "APP", icon: "safari.fill", description: "Buka peramban web default", systemAction: .launchApp, targetApp: "com.apple.Safari"),
                PadControlItemModel(title: "System Settings", badgeDisplay: "APP", icon: "gearshape.fill", description: "Buka Pengaturan Sistem macOS", systemAction: .launchApp, targetApp: "com.apple.systempreferences")
            ]
        )
    ]

    static var categories: [PadControlCategory] {
        var allList: [PadControlItemModel] = []
        for cat in subcategories {
            allList.append(contentsOf: cat.items)
        }
        let allCategory = PadControlCategory(
            id: "cat.all",
            name: "Semua",
            icon: "slider.horizontal.3",
            themeColor: Color.indigo,
            subtitle: "Pusat Kontrol macOS",
            description: "Akses cepat media, audio, jendela, dan perintah sistem Mac",
            items: allList
        )
        return [allCategory] + subcategories
    }
}

struct PadControlCenterView: View {
    @ObservedObject var connection: PadConnectionManager
    var onActionFeedback: ((String) -> Void)? = nil

    @State private var selectedCategoryId: String = "cat.all"
    @State private var searchText: String = ""
    @State private var feedbackMessage: String?
    @State private var pendingDestructiveItem: PadControlItemModel?

    private var categories: [PadControlCategory] {
        PadControlCenterData.categories
    }

    private var selectedCategory: PadControlCategory {
        categories.first(where: { $0.id == selectedCategoryId }) ?? categories[0]
    }

    private var filteredItems: [PadControlItemModel] {
        let base = selectedCategory.items
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return base
        }
        let query = searchText.lowercased()
        return base.filter {
            $0.title.lowercased().contains(query) ||
            $0.badgeDisplay.lowercased().contains(query) ||
            $0.description.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // 1. Horizontal Category Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { cat in
                        let isSelected = (cat.id == selectedCategory.id)
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedCategoryId = cat.id
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.white : cat.themeColor)

                                Text(cat.name)
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? Color.white : EvoTheme.textPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? cat.themeColor : EvoTheme.panel,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(isSelected ? Color.white.opacity(0.25) : EvoTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }

            // 2. Info Banner / Header Card
            HStack(spacing: 12) {
                Image(systemName: selectedCategory.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(selectedCategory.themeColor)
                    .frame(width: 38, height: 38)
                    .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(selectedCategory.themeColor.opacity(0.35), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(selectedCategory.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(EvoTheme.textPrimary)

                        Text("•")
                            .foregroundStyle(EvoTheme.textTertiary)

                        Text("\(filteredItems.count) kontrol")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(EvoTheme.textSecondary)
                    }

                    Text(selectedCategory.description)
                        .font(.system(size: 11))
                        .foregroundStyle(EvoTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Subtitle Tag
                Text(selectedCategory.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selectedCategory.themeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(selectedCategory.themeColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selectedCategory.themeColor.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(EvoTheme.border, lineWidth: 1)
            )

            // 3. Quick Search Filter
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(EvoTheme.textTertiary)

                TextField("Cari kontrol sistem, media, audio, atau jendela...", text: $searchText)
                    .font(.system(size: 12))
                    .foregroundStyle(EvoTheme.textPrimary)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(EvoTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(EvoTheme.border, lineWidth: 1)
            )

            // 4. Control Cards Grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                    ForEach(filteredItems) { item in
                        Button {
                            executeItem(item)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(selectedCategory.themeColor)
                                    .frame(width: 28, height: 28)
                                    .background(EvoTheme.surface, in: RoundedRectangle(cornerRadius: 7))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(EvoTheme.textPrimary)
                                        .lineLimit(1)

                                    Text(item.description)
                                        .font(.system(size: 10))
                                        .foregroundStyle(EvoTheme.textSecondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)

                                Text(item.badgeDisplay)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(EvoTheme.textPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(EvoTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(EvoTheme.borderStrong, lineWidth: 1)
                                    )
                            }
                            .padding(8)
                            .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(EvoTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!connection.isAuthenticated)
                    }
                }
                .padding(.vertical, 2)
            }

            // 5. Feedback Banner
            if let feedback = feedbackMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255))
                    Text(feedback)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EvoTheme.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(EvoTheme.surface, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(EvoTheme.borderStrong, lineWidth: 1)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(10)
        .background(EvoTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(EvoTheme.border, lineWidth: 1)
        )
        .confirmationDialog(
            "Konfirmasi Perintah Sistem",
            isPresented: Binding(
                get: { pendingDestructiveItem != nil },
                set: { if !$0 { pendingDestructiveItem = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = pendingDestructiveItem {
                Button("Jalankan \(item.title)", role: .destructive) {
                    performItemExecution(item)
                    pendingDestructiveItem = nil
                }
            }
            Button("Batal", role: .cancel) {
                pendingDestructiveItem = nil
            }
        } message: {
            if let item = pendingDestructiveItem {
                Text("Apakah Anda yakin ingin menjalankan aksi '\(item.title)' pada Mac?")
            }
        }
    }

    private func executeItem(_ item: PadControlItemModel) {
        if item.systemAction == .sleep || item.systemAction == .lockScreen {
            pendingDestructiveItem = item
            return
        }
        performItemExecution(item)
    }

    private func performItemExecution(_ item: PadControlItemModel) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        if let media = item.mediaKey {
            connection.sendMediaKey(media)
            showFeedback("Media: \(item.title)")
            onActionFeedback?("Media: \(item.title)")
        } else if let sys = item.systemAction {
            connection.sendSystemAction(sys, targetApp: item.targetApp)
            showFeedback("Sistem: \(item.title)")
            onActionFeedback?("Sistem: \(item.title)")
        } else if let code = item.customKeyCode {
            connection.sendCustomShortcut(keyCode: code, modifiers: item.customModifiers)
            showFeedback("Aksi: \(item.title)")
            onActionFeedback?("Aksi: \(item.title)")
        }
    }

    private func showFeedback(_ text: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            feedbackMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if feedbackMessage == text {
                    feedbackMessage = nil
                }
            }
        }
    }
}

