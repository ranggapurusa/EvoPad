import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// M5 — Customizable Workspace & Adaptive Grid Control Surface (integrating M5.1, M5.2, M5.3, M5.4 + M4 Media/System strip).
struct PadControlPanelView: View {
    @ObservedObject var connection: PadConnectionManager
    @ObservedObject var workspaceStore = PadWorkspaceStore.shared
    @ObservedObject var macroStore = PadMacroStore.shared
    var onActionFeedback: ((String) -> Void)? = nil

    @State private var isEditingLayout = false
    @State private var showQuickMediaStrip = false
    @State private var showingWorkspaceManager = false
    @State private var showingItemEditor = false
    @State private var editingItem: ControlItem?
    @State private var newItemRow: Int = 0
    @State private var newItemCol: Int = 0
    @State private var draggedItemId: String?
    @State private var pendingDestructiveItem: ControlItem?

    var body: some View {
        let workspace = workspaceStore.activeWorkspace
        let layout = workspace.layout
        let rowHeight: CGFloat = workspace.settings.oneHandedCompactMode ? 50 : 58
        let spacing: CGFloat = 8

        VStack(spacing: 10) {
            // M5.1 Workspace Switcher & Mode Bar
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(workspaceStore.workspaces) { ws in
                            let isSelected = (ws.id == workspace.id)
                            Button {
                                workspaceStore.switchWorkspace(to: ws.id)
                                onActionFeedback?("Workspace aktif: \(ws.name)")
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: ws.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(ws.name)
                                        .font(.system(size: 11, weight: .semibold))
                                    if ws.isDefault {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 8))
                                            .foregroundStyle(.yellow)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(
                                        isSelected
                                            ? ws.accentColor.swiftUIColor
                                            : Color.white.opacity(0.08)
                                    )
                                )
                                .foregroundStyle(isSelected ? .white : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 4)

                // Toggle Quick Media/System Strip (M4 compatibility)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showQuickMediaStrip.toggle()
                    }
                } label: {
                    Image(systemName: "slider.horizontal.below.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(showQuickMediaStrip ? EvoTheme.accent : EvoTheme.keySurface)
                        )
                        .foregroundStyle(showQuickMediaStrip ? .white : EvoTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Tampilkan/Sembunyikan Media & System Strip")

                // Toggle Layout Editor vs Preview/Normal Mode (M5.2)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isEditingLayout.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isEditingLayout ? "checkmark.circle.fill" : "square.grid.3x3.topleft.filled")
                            .font(.system(size: 11, weight: .semibold))
                        Text(isEditingLayout ? "Selesai" : "Edit Grid")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isEditingLayout ? Color.orange : EvoTheme.keySurface)
                    )
                    .foregroundStyle(isEditingLayout ? .white : EvoTheme.textSecondary)
                }
                .buttonStyle(.plain)

                // Open Workspace Manager & Import/Export (M5.1 / M5.4)
                Button {
                    showingWorkspaceManager = true
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(EvoTheme.keySurface))
                        .foregroundStyle(EvoTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            // M5.2 Layout Editor Toolbar (only visible in Edit Mode)
            if isEditingLayout {
                HStack(spacing: 10) {
                    Label("MODE EDITOR LAYOUT", systemImage: "hand.draw.fill")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)

                    Spacer()

                    HStack(spacing: 4) {
                        Text("Kolom: \(layout.columns)")
                            .font(.caption2.weight(.semibold))
                        Stepper(
                            "",
                            value: Binding(
                                get: { layout.columns },
                                set: { workspaceStore.resizeGrid(columns: $0, rows: layout.rows) }
                            ),
                            in: PadWorkspaceSchema.minColumns...PadWorkspaceSchema.maxColumns
                        )
                        .labelsHidden()
                        .scaleEffect(0.8)
                    }

                    HStack(spacing: 4) {
                        Text("Baris: \(layout.rows)")
                            .font(.caption2.weight(.semibold))
                        Stepper(
                            "",
                            value: Binding(
                                get: { layout.rows },
                                set: { workspaceStore.resizeGrid(columns: layout.columns, rows: $0) }
                            ),
                            in: PadWorkspaceSchema.minRows...PadWorkspaceSchema.maxRows
                        )
                        .labelsHidden()
                        .scaleEffect(0.8)
                    }

                    Button {
                        if let pos = layout.firstAvailablePosition(for: .small) {
                            newItemRow = pos.row
                            newItemCol = pos.col
                        } else {
                            newItemRow = 0
                            newItemCol = 0
                        }
                        editingItem = nil
                        showingItemEditor = true
                    } label: {
                        Label("Tambah Tombol", systemImage: "plus.circle.fill")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(EvoTheme.accent))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            // M5.2 Adaptive 2D Coordinate Grid Canvas
            GeometryReader { geo in
                let totalSpacingW = spacing * CGFloat(max(0, layout.columns - 1))
                let cellWidth = max(44, (geo.size.width - totalSpacingW) / CGFloat(layout.columns))
                let occupied = layout.occupiedCells()

                ZStack(alignment: .topLeading) {
                    // Render empty slot placeholders in Layout Editor mode (or when workspace has no buttons)
                    if isEditingLayout || layout.items.isEmpty {
                        ForEach(0..<layout.rows, id: \.self) { r in
                            ForEach(0..<layout.columns, id: \.self) { c in
                                if !occupied.contains(GridCell(row: r, col: c)) {
                                    emptySlotView(row: r, col: c, width: cellWidth, height: rowHeight)
                                        .offset(
                                            x: CGFloat(c) * (cellWidth + spacing),
                                            y: CGFloat(r) * (rowHeight + spacing)
                                        )
                                }
                            }
                        }
                    }

                    // Render placed ControlItems with support for 1x1, 2x1, and 2x2 spans
                    ForEach(layout.items) { item in
                        let w = cellWidth * CGFloat(item.size.colSpan) + spacing * CGFloat(item.size.colSpan - 1)
                        let h = rowHeight * CGFloat(item.size.rowSpan) + spacing * CGFloat(item.size.rowSpan - 1)
                        let x = CGFloat(item.col) * (cellWidth + spacing)
                        let y = CGFloat(item.row) * (rowHeight + spacing)

                        controlItemButton(
                            item: item,
                            workspace: workspace,
                            width: w,
                            height: h
                        )
                        .offset(x: x, y: y)
                    }
                }
            }
            .frame(height: CGFloat(layout.rows) * rowHeight + CGFloat(max(0, layout.rows - 1)) * spacing)
            .padding(10)
            .background(EvoTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(EvoTheme.border, lineWidth: 1)
            )

            // Collapsible Quick Media & System Strip (M4.4 Instant Access)
            if showQuickMediaStrip {
                quickMediaAndSystemStrip
            }
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $showingWorkspaceManager) {
            PadWorkspaceManagerSheet(workspaceStore: workspaceStore)
        }
        .sheet(isPresented: $showingItemEditor) {
            PadControlItemEditorSheet(
                workspaceStore: workspaceStore,
                macroStore: macroStore,
                existingItem: editingItem,
                initialRow: newItemRow,
                initialCol: newItemCol
            )
        }
        .confirmationDialog(
            "Konfirmasi System Action",
            isPresented: Binding(
                get: { pendingDestructiveItem != nil },
                set: { if !$0 { pendingDestructiveItem = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = pendingDestructiveItem {
                Button("Jalankan '\(item.label)'", role: .destructive) {
                    executeItemAction(item, workspace: workspace)
                    pendingDestructiveItem = nil
                }
            }
            Button("Batal", role: .cancel) {
                pendingDestructiveItem = nil
            }
        } message: {
            if let item = pendingDestructiveItem {
                Text("Apakah Anda yakin ingin menjalankan '\(item.label)' pada Mac?")
            }
        }
    }

    // MARK: - Grid Item & Empty Slot Views

    private func emptySlotView(row: Int, col: Int, width: CGFloat, height: CGFloat) -> some View {
        Button {
            newItemRow = row
            newItemCol = col
            editingItem = nil
            showingItemEditor = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text("\(row + 1),\(col + 1)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(.white.opacity(0.35))
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.white.opacity(0.22))
            )
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            handleDrop(providers: providers, targetRow: row, targetCol: col)
        }
    }

    private func controlItemButton(
        item: ControlItem,
        workspace: Workspace,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let isActionDisabled = !isEditingLayout && !connection.isAuthenticated

        return ZStack(alignment: .topTrailing) {
            Button {
                if isEditingLayout {
                    editingItem = item
                    showingItemEditor = true
                } else {
                    triggerControlItem(item, workspace: workspace)
                }
            } label: {
                HStack(spacing: item.size == .small ? 6 : 10) {
                    Image(systemName: item.icon)
                        .font(.system(size: item.size == .large ? 20 : 15, weight: .semibold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .font(.system(size: item.size == .large ? 13 : 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if workspace.settings.showShortcutSubtitles {
                            Text(item.action.badgeText)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(width: width, height: height)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(item.color.swiftUIColor.opacity(isActionDisabled ? 0.15 : 0.35))
                        .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isEditingLayout ? Color.orange.opacity(0.9) : EvoTheme.border,
                            lineWidth: isEditingLayout ? 1.5 : 1
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(isActionDisabled)
            .onDrag {
                draggedItemId = item.id
                return NSItemProvider(object: item.id as NSString)
            }
            .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                handleDrop(providers: providers, targetRow: item.row, targetCol: item.col)
            }
            .contextMenu {
                Button {
                    editingItem = item
                    showingItemEditor = true
                } label: {
                    Label("Kustomisasi Tombol", systemImage: "slider.horizontal.3")
                }

                Button(role: .destructive) {
                    workspaceStore.removeControlItem(itemId: item.id)
                } label: {
                    Label("Hapus Tombol dari Grid", systemImage: "trash")
                }
            }

            if isEditingLayout {
                Button {
                    workspaceStore.removeControlItem(itemId: item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white, .red)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider], targetRow: Int, targetCol: Int) -> Bool {
        if let localId = draggedItemId {
            let moved = workspaceStore.moveControlItem(itemId: localId, toRow: targetRow, toCol: targetCol)
            draggedItemId = nil
            return moved
        }
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let itemId = reading as? String else { return }
            DispatchQueue.main.async {
                _ = workspaceStore.moveControlItem(itemId: itemId, toRow: targetRow, toCol: targetCol)
            }
        }
        return true
    }

    private func triggerControlItem(_ item: ControlItem, workspace: Workspace) {
        if workspace.settings.hapticFeedback {
            #if canImport(UIKit)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif
        }

        if workspace.settings.confirmDestructiveSystemActions,
           item.action.kind == .system,
           (item.action.actionReferenceId == PadSystemControlAction.sleep.rawValue ||
            item.action.actionReferenceId == PadSystemControlAction.lockScreen.rawValue) {
            pendingDestructiveItem = item
            return
        }

        executeItemAction(item, workspace: workspace)
    }

    private func executeItemAction(_ item: ControlItem, workspace: Workspace) {
        let summary = PadWorkspaceActionDispatcher.execute(
            item.action,
            itemLabel: item.label,
            connection: connection,
            macroStore: macroStore
        )
        onActionFeedback?("[\(workspace.name)] \(summary)")
    }

    // MARK: - Quick Media & System Strip (M4.4 Compatibility)

    private var quickMediaAndSystemStrip: some View {
        HStack(spacing: 8) {
            ForEach([PadMediaControlKey.previousTrack, .playPause, .nextTrack, .volumeDown, .volumeUp, .mute]) { key in
                Button {
                    connection.sendMediaKey(key)
                    onActionFeedback?("Media: \(key.title)")
                } label: {
                    Image(systemName: key.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(EvoTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!connection.isAuthenticated)
            }

            Divider().frame(height: 24).background(EvoTheme.border)

            ForEach([PadSystemControlAction.screenshot, .lockScreen, .sleep]) { action in
                Button {
                    connection.sendSystemAction(action)
                    onActionFeedback?("System: \(action.title)")
                } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(action == .screenshot ? EvoTheme.accent : Color.orange)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(EvoTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!connection.isAuthenticated)
            }
        }
        .padding(8)
        .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(EvoTheme.border, lineWidth: 1)
        )
    }
}
