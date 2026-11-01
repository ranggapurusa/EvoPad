import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// M5.3 — Customization sheet for creating or editing a `ControlItem` (label, icon, color, category, size, grid slot, and action).
struct PadControlItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var workspaceStore: PadWorkspaceStore
    @ObservedObject var macroStore: PadMacroStore

    let existingItem: ControlItem?
    let initialRow: Int
    let initialCol: Int

    @State private var label: String = ""
    @State private var icon: String = "command"
    @State private var color: ControlColor = .indigo
    @State private var category: ControlCategory = .shortcut
    @State private var size: ControlSize = .small
    @State private var row: Int = 0
    @State private var col: Int = 0

    // Action selection state
    @State private var actionKind: ControlActionKind = .standardShortcut
    @State private var selectedStandardShortcut: PadStandardShortcut = .copy
    @State private var customKeyCode: UInt16 = 8 // C
    @State private var customCmd: Bool = true
    @State private var customShift: Bool = false
    @State private var customOpt: Bool = false
    @State private var customCtrl: Bool = false
    @State private var selectedMacroId: String = "preset.copyAll"
    @State private var selectedMediaKey: PadMediaControlKey = .playPause
    @State private var selectedSystemAction: PadSystemControlAction = .screenshot
    @State private var targetAppBundleId: String = "com.apple.Terminal"

    @State private var validationMessage: String?

    private static let availableIcons: [String] = [
        "doc.on.doc", "doc.on.clipboard", "scissors", "arrow.uturn.backward",
        "arrow.uturn.forward", "magnifyingglass", "rectangle.3.group", "rectangle.stack",
        "terminal.fill", "hammer.fill", "chevron.left.forwardslash.chevron.right", "text.bubble",
        "playpause.fill", "backward.fill", "forward.fill", "speaker.wave.3.fill",
        "speaker.wave.1.fill", "speaker.slash.fill", "camera.viewfinder", "lock.fill",
        "moon.fill", "plus.magnifyingglass", "minus.magnifyingglass", "paintbrush.pointed.fill",
        "sparkles.rectangle.stack.fill", "bolt.fill", "globe", "folder.fill",
        "gearshape.fill", "app.badge", "keyboard", "display"
    ]

    private static let selectableKeys: [(code: UInt16, label: String)] = [
        (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"),
        (4, "H"), (34, "I"), (38, "J"), (40, "K"), (37, "L"), (46, "M"), (45, "N"),
        (31, "O"), (35, "P"), (12, "Q"), (15, "R"), (1, "S"), (17, "T"), (32, "U"),
        (9, "V"), (13, "W"), (7, "X"), (16, "Y"), (6, "Z"),
        (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"),
        (22, "6"), (26, "7"), (28, "8"), (25, "9"), (29, "0"),
        (24, "= / +"), (27, "-"), (33, "["), (30, "]"), (44, "/"), (43, ","), (47, "."),
        (36, "Return ⏎"), (48, "Tab ⇥"), (49, "Space"), (51, "Delete ⌫"), (53, "Esc"),
        (123, "← Left"), (124, "→ Right"), (126, "↑ Up"), (125, "↓ Down")
    ]

    init(
        workspaceStore: PadWorkspaceStore,
        macroStore: PadMacroStore = .shared,
        existingItem: ControlItem? = nil,
        initialRow: Int = 0,
        initialCol: Int = 0
    ) {
        self.workspaceStore = workspaceStore
        self.macroStore = macroStore
        self.existingItem = existingItem
        self.initialRow = initialRow
        self.initialCol = initialCol
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tampilan Tombol (M5.3)") {
                    TextField("Label Tombol", text: $label)

                    Picker("Kategori", selection: $category) {
                        ForEach(ControlCategory.allCases) { cat in
                            Label(cat.title, systemImage: cat.symbol).tag(cat)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Warna Tombol")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                            ForEach(ControlColor.allCases) { itemColor in
                                Button {
                                    color = itemColor
                                } label: {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(itemColor.swiftUIColor)
                                            .frame(width: 14, height: 14)
                                        Text(itemColor.title)
                                            .font(.caption2.weight(.semibold))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(color == itemColor ? itemColor.swiftUIColor.opacity(0.22) : Color.secondary.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(color == itemColor ? itemColor.swiftUIColor : .clear, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ikon (SF Symbols)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                            ForEach(Self.availableIcons, id: \.self) { sym in
                                Button {
                                    icon = sym
                                } label: {
                                    Image(systemName: sym)
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(width: 34, height: 34)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(icon == sym ? color.swiftUIColor.opacity(0.25) : Color.secondary.opacity(0.1))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(icon == sym ? color.swiftUIColor : .clear, lineWidth: 1.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Ukuran & Posisi Grid (M5.2)") {
                    Picker("Ukuran Tombol", selection: $size) {
                        ForEach(ControlSize.allCases) { sz in
                            Text(sz.title).tag(sz)
                        }
                    }
                    .pickerStyle(.segmented)

                    let maxRow = max(0, workspaceStore.activeWorkspace.layout.rows - size.rowSpan)
                    let maxCol = max(0, workspaceStore.activeWorkspace.layout.columns - size.colSpan)

                    Stepper("Baris (Row): \(row + 1)", value: $row, in: 0...maxRow)
                    Stepper("Kolom (Col): \(col + 1)", value: $col, in: 0...maxCol)
                }

                Section("Penugasan Action (M5.3)") {
                    Picker("Tipe Action", selection: $actionKind) {
                        ForEach(ControlActionKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .onChange(of: actionKind) { _, newKind in
                        syncCategoryAndDefaults(for: newKind)
                    }

                    actionConfigurationFields
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(existingItem == nil ? "Tambah Tombol Kontrol" : "Edit Tombol Kontrol")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") { saveItem() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: populateInitialState)
        }
    }

    @ViewBuilder
    private var actionConfigurationFields: some View {
        switch actionKind {
        case .standardShortcut:
            Picker("Shortcut Standar", selection: $selectedStandardShortcut) {
                ForEach(PadStandardShortcut.allCases) { sc in
                    Text("\(sc.title) (\(sc.chordDescription))").tag(sc)
                }
            }
            .onChange(of: selectedStandardShortcut) { _, newValue in
                if label.isEmpty {
                    label = newValue.title
                    icon = newValue.symbol
                }
            }

        case .customShortcut:
            VStack(alignment: .leading, spacing: 8) {
                Text("Modifier Keys")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    modifierToggle("⌘ Cmd", isOn: $customCmd)
                    modifierToggle("⇧ Shift", isOn: $customShift)
                    modifierToggle("⌥ Opt", isOn: $customOpt)
                    modifierToggle("⌃ Ctrl", isOn: $customCtrl)
                }
            }
            Picker("Tombol Utama", selection: $customKeyCode) {
                ForEach(Self.selectableKeys, id: \.code) { entry in
                    Text(entry.label).tag(entry.code)
                }
            }

        case .macro:
            if macroStore.macros.isEmpty {
                Text("Belum ada macro tersimpan di PadMacroStore.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Pilih Macro", selection: $selectedMacroId) {
                    ForEach(macroStore.macros) { macro in
                        Text("\(macro.name) (\(macro.steps.count) langkah)").tag(macro.id)
                    }
                }
                .onChange(of: selectedMacroId) { _, newId in
                    if let found = macroStore.macros.first(where: { $0.id == newId }), label.isEmpty {
                        label = found.name
                        icon = found.icon
                    }
                }
            }

        case .media:
            Picker("Media Key", selection: $selectedMediaKey) {
                ForEach(PadMediaControlKey.allCases) { key in
                    Label(key.title, systemImage: key.symbol).tag(key)
                }
            }
            .onChange(of: selectedMediaKey) { _, newKey in
                if label.isEmpty {
                    label = newKey.title
                    icon = newKey.symbol
                }
            }

        case .system:
            Picker("System Action", selection: $selectedSystemAction) {
                Text("Screenshot").tag(PadSystemControlAction.screenshot)
                Text("Lock Screen").tag(PadSystemControlAction.lockScreen)
                Text("Sleep Mac").tag(PadSystemControlAction.sleep)
                Text("Launch App (Bundle ID)").tag(PadSystemControlAction.launchApp)
            }
            if selectedSystemAction == .launchApp {
                TextField("Bundle ID (mis. com.apple.Terminal)", text: $targetAppBundleId)
                    .autocorrectionDisabled()
            }
        }
    }

    private func modifierToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn.wrappedValue ? Color.indigo.opacity(0.24) : Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isOn.wrappedValue ? Color.indigo : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func syncCategoryAndDefaults(for kind: ControlActionKind) {
        switch kind {
        case .standardShortcut, .customShortcut:
            category = .shortcut
        case .macro:
            category = .macro
            if let first = macroStore.macros.first, !macroStore.macros.contains(where: { $0.id == selectedMacroId }) {
                selectedMacroId = first.id
            }
        case .media:
            category = .media
        case .system:
            category = .system
        }
    }

    private func populateInitialState() {
        if let item = existingItem {
            label = item.label
            icon = item.icon
            color = item.color
            category = item.category
            size = item.size
            row = item.row
            col = item.col
            actionKind = item.action.kind

            switch item.action.kind {
            case .standardShortcut:
                selectedStandardShortcut = PadStandardShortcut(rawValue: item.action.actionReferenceId) ?? .copy
            case .customShortcut:
                customKeyCode = item.action.customKeyCode ?? 8
                let mods = Set(item.action.customModifiers ?? [.cmd])
                customCmd = mods.contains(.cmd)
                customShift = mods.contains(.shift)
                customOpt = mods.contains(.alt)
                customCtrl = mods.contains(.ctrl)
            case .macro:
                selectedMacroId = item.action.actionReferenceId
            case .media:
                selectedMediaKey = PadMediaControlKey(rawValue: item.action.actionReferenceId) ?? .playPause
            case .system:
                selectedSystemAction = PadSystemControlAction(rawValue: item.action.actionReferenceId) ?? .screenshot
                targetAppBundleId = item.action.targetApp ?? "com.apple.Terminal"
            }
        } else {
            row = initialRow
            col = initialCol
            label = selectedStandardShortcut.title
            icon = selectedStandardShortcut.symbol
        }
    }

    private func buildAction() -> ControlAction {
        switch actionKind {
        case .standardShortcut:
            return .standardShortcut(selectedStandardShortcut)
        case .customShortcut:
            var mods: [PadModifierFlagV2] = []
            if customCmd { mods.append(.cmd) }
            if customShift { mods.append(.shift) }
            if customOpt { mods.append(.alt) }
            if customCtrl { mods.append(.ctrl) }
            return .customShortcut(keyCode: customKeyCode, modifiers: mods)
        case .macro:
            return .macro(id: selectedMacroId)
        case .media:
            return .media(selectedMediaKey)
        case .system:
            let app = selectedSystemAction == .launchApp ? targetAppBundleId.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            return .system(selectedSystemAction, targetApp: app)
        }
    }

    private func saveItem() {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else {
            validationMessage = "Label tombol tidak boleh kosong."
            return
        }

        let builtAction = buildAction()
        let item = ControlItem(
            id: existingItem?.id ?? UUID().uuidString,
            label: trimmedLabel,
            icon: icon,
            color: color,
            category: category,
            row: row,
            col: col,
            size: size,
            order: existingItem?.order ?? workspaceStore.activeWorkspace.layout.items.count,
            action: builtAction
        )

        let success: Bool
        if existingItem != nil {
            success = workspaceStore.updateControlItem(item)
        } else {
            success = workspaceStore.addControlItem(item)
        }

        if success {
            dismiss()
        } else {
            validationMessage = "Tidak cukup ruang pada grid untuk ukuran tombol ini. Kurangi ukuran atau tambah baris grid."
        }
    }
}
