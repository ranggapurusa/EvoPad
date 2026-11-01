import SwiftUI

struct PadContentView: View {
    @StateObject private var connection = PadConnectionManager()
    @StateObject private var macroStore = PadMacroStore.shared
    @StateObject private var workspaceStore = PadWorkspaceStore.shared
    @State private var inputFeedback = "Siap menerima gesture"
    @State private var showingQRScanner = false
    @State private var showingVirtualKeyboard = false
    @State private var showingMacroEditor = false
    @State private var showingWorkspaceManager = false
    @State private var editingMacro: PadMacroDefinition?
    @State private var activeDockTab: PadDockTab = .control

    enum PadDockTab: String, CaseIterable, Identifiable {
        case control = "Workspace"
        case shortcuts = "Shortcuts"
        case macros = "Macros"
        var id: String { rawValue }
    }

    // Modifier Toggles for Custom Combinations
    @State private var isCmdActive = false
    @State private var isOptActive = false
    @State private var isCtrlActive = false
    @State private var isShiftActive = false

    private var selectedModifiers: [PadModifierFlagV2] {
        var mods: [PadModifierFlagV2] = []
        if isCmdActive { mods.append(.cmd) }
        if isOptActive { mods.append(.alt) }
        if isCtrlActive { mods.append(.ctrl) }
        if isShiftActive { mods.append(.shift) }
        return mods
    }

    var body: some View {
        VStack(spacing: 12) {
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

                Button {
                    showingVirtualKeyboard.toggle()
                } label: {
                    Image(systemName: showingVirtualKeyboard ? "keyboard.chevron.compact.down.fill" : "keyboard.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(showingVirtualKeyboard ? .indigo : .secondary)

                Circle()
                    .fill(connection.isAuthenticated ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(connection.isAuthenticated ? "CONNECTED" : (connection.isConnected ? "AUTHENTICATING" : "SEARCHING"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
            }

            // Trackpad Touch Surface
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

            // M3.1 Shortcut Engine Bar & Modifiers
            VStack(spacing: 8) {
                // Modifier Bar (Command, Option, Control, Shift)
                HStack(spacing: 8) {
                    modifierToggle(title: "⌘ Cmd", isActive: $isCmdActive)
                    modifierToggle(title: "⌥ Opt", isActive: $isOptActive)
                    modifierToggle(title: "⌃ Ctrl", isActive: $isCtrlActive)
                    modifierToggle(title: "⇧ Shift", isActive: $isShiftActive)

                    if !selectedModifiers.isEmpty {
                        Button("Lepas") {
                            isCmdActive = false
                            isOptActive = false
                            isCtrlActive = false
                            isShiftActive = false
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    }
                }

                // Dock Selector Tabs (Shortcuts / Macros / Control)
                HStack(spacing: 6) {
                    Picker("Mode Dock", selection: $activeDockTab) {
                        ForEach(PadDockTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)

                    Spacer()

                    if activeDockTab == .macros {
                        Button {
                            editingMacro = nil
                            showingMacroEditor = true
                        } label: {
                            Label("Tambah", systemImage: "plus")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(.indigo)
                        .controlSize(.small)
                    }
                }

                if activeDockTab == .shortcuts {
                    // Standard Shortcut Dock
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PadStandardShortcut.allCases) { shortcut in
                                Button {
                                    triggerShortcut(shortcut)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: shortcut.symbol)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(shortcut.title)
                                            .font(.system(size: 12, weight: .medium))
                                        Text(shortcut.chordDescription)
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .disabled(!connection.isAuthenticated)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                } else if activeDockTab == .macros {
                    // M4.1 Macro Presets Dock
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(macroStore.macros) { macro in
                                Button {
                                    connection.sendMacro(macroId: macro.id, steps: macro.steps)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: macro.icon)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.indigo)
                                        Text(macro.name)
                                            .font(.system(size: 12, weight: .medium))
                                        Text("(\(macro.steps.count))")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .disabled(!connection.isAuthenticated)
                                .contextMenu {
                                    Button {
                                        editingMacro = macro
                                        showingMacroEditor = true
                                    } label: {
                                        Label("Edit Macro", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        macroStore.deleteMacro(id: macro.id)
                                    } label: {
                                        Label("Hapus Macro", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                } else {
                    // M5 Workspace & Custom Layout Control Surface
                    PadControlPanelView(
                        connection: connection,
                        workspaceStore: workspaceStore,
                        macroStore: macroStore,
                        onActionFeedback: { message in
                            inputFeedback = message
                        }
                    )
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            // Status & Feedback
            VStack(alignment: .leading, spacing: 4) {
                Text(inputFeedback)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .accessibilityIdentifier("evopad.inputFeedback")

                Text("Mac: \(connection.macFeedback)")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.48))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .accessibilityIdentifier("evopad.macFeedback")
            }

            // Bottom Mouse Buttons
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

            // M3.2 Virtual Keyboard Drawer
            if showingVirtualKeyboard {
                PadVirtualKeyboardView(
                    connection: connection,
                    isCmdActive: $isCmdActive,
                    isOptActive: $isOptActive,
                    isCtrlActive: $isCtrlActive,
                    isShiftActive: $isShiftActive
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(16)
        .animation(.easeInOut(duration: 0.22), value: showingVirtualKeyboard)
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
        .sheet(isPresented: $showingMacroEditor) {
            PadMacroEditorSheet(existingMacro: editingMacro)
        }
    }

    private func modifierToggle(title: String, isActive: Binding<Bool>) -> some View {
        Button {
            isActive.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isActive.wrappedValue ? Color.indigo : Color.white.opacity(0.08))
                .foregroundStyle(isActive.wrappedValue ? .white : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!connection.isAuthenticated)
    }

    private func triggerShortcut(_ shortcut: PadStandardShortcut) {
        let activeMods = selectedModifiers
        if activeMods.isEmpty {
            connection.sendShortcut(shortcut)
        } else {
            // Merge custom toggled modifiers with shortcut key
            var merged = Set(shortcut.modifiers)
            for mod in activeMods {
                merged.insert(mod)
            }
            connection.sendCustomShortcut(keyCode: shortcut.keyCode, modifiers: Array(merged))
        }
    }
}
