import Foundation
import SwiftUI

// MARK: - Import / Export Types & Errors (M5.4)

enum WorkspaceImportConflictPolicy: String, CaseIterable, Identifiable {
    case keepBoth           // Safe default: never overwrites, creates new ID & suffix if needed
    case skipConflicting    // Keeps existing workspaces untouched, ignores conflicting imports
    case overwriteApproved  // Explicit user consent to replace matching workspace ID/name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepBoth: return "Simpan Keduanya (Aman)"
        case .skipConflicting: return "Lewati yang Bentrok"
        case .overwriteApproved: return "Timpa Workspace Lama"
        }
    }
}

enum WorkspaceImportError: LocalizedError, Equatable {
    case emptyPayload
    case invalidJSON(String)
    case unsupportedSchemaVersion(Int)
    case noWorkspacesFound
    case invalidWorkspaceData(String)

    var errorDescription: String? {
        switch self {
        case .emptyPayload:
            return "File konfigurasi kosong."
        case .invalidJSON(let detail):
            return "Format JSON rusak atau tidak valid: \(detail)"
        case .unsupportedSchemaVersion(let version):
            return "Versi schema (\(version)) tidak kompatibel dengan aplikasi ini (didukung: v\(PadWorkspaceSchema.minimumSupportedVersion)–v\(PadWorkspaceSchema.currentVersion))."
        case .noWorkspacesFound:
            return "Tidak ada data workspace di dalam file."
        case .invalidWorkspaceData(let reason):
            return "Data workspace tidak valid: \(reason)"
        }
    }
}

struct WorkspaceImportPreview: Equatable {
    let bundle: WorkspaceExportBundle
    let conflictingWorkspaceNames: [String]
    let hadCollisionRepairs: Bool

    var hasConflicts: Bool {
        !conflictingWorkspaceNames.isEmpty
    }
}

// MARK: - Action Execution Dispatcher (M5.3)

enum PadWorkspaceActionDispatcher {
    /// Dispatches a `ControlAction` using existing M3/M4 engines on `PadConnectionManager` and `PadMacroStore`.
    @discardableResult
    static func execute(
        _ action: ControlAction,
        itemLabel: String,
        connection: PadConnectionManager,
        macroStore: PadMacroStore = .shared
    ) -> String {
        switch action.kind {
        case .standardShortcut:
            guard let shortcut = PadStandardShortcut(rawValue: action.actionReferenceId) else {
                return "Shortcut tidak ditemukan (\(action.actionReferenceId))"
            }
            connection.sendShortcut(shortcut)
            return "\(shortcut.title) (\(shortcut.chordDescription))"

        case .customShortcut:
            guard let keyCode = action.customKeyCode else {
                return "KeyCode shortcut kosong"
            }
            let modifiers = action.customModifiers ?? []
            connection.sendCustomShortcut(keyCode: keyCode, modifiers: modifiers)
            return "\(itemLabel) (\(action.badgeText))"

        case .macro:
            guard let macro = macroStore.macros.first(where: { $0.id == action.actionReferenceId }) else {
                return "Macro tidak ditemukan (\(action.actionReferenceId))"
            }
            connection.sendMacro(macroId: macro.id, steps: macro.steps)
            return "Macro: \(macro.name)"

        case .media:
            guard let key = PadMediaControlKey(rawValue: action.actionReferenceId) else {
                return "Media key tidak valid (\(action.actionReferenceId))"
            }
            connection.sendMediaKey(key)
            return "Media: \(key.title)"

        case .system:
            guard let sys = PadSystemControlAction(rawValue: action.actionReferenceId) else {
                return "System action tidak valid (\(action.actionReferenceId))"
            }
            connection.sendSystemAction(sys, targetApp: action.targetApp)
            return "System: \(itemLabel)"
        }
    }
}

// MARK: - PadWorkspaceStore (M5.1, M5.2, M5.3, M5.4)

final class PadWorkspaceStore: ObservableObject {
    static let shared = PadWorkspaceStore()

    @Published private(set) var workspaces: [Workspace] = []
    @Published var activeWorkspaceId: String = "preset.general" {
        didSet {
            userDefaults.set(activeWorkspaceId, forKey: activeWorkspaceKey)
        }
    }

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let activeWorkspaceKey: String
    private let fileURL: URL?

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "id.evonex.evopad.workspaces.v1",
        activeWorkspaceKey: String = "id.evonex.evopad.activeWorkspaceId.v1",
        customFileURL: URL? = nil
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.activeWorkspaceKey = activeWorkspaceKey
        if let customFileURL {
            self.fileURL = customFileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let dir = appSupport?.appendingPathComponent("EvoPad", isDirectory: true)
            if let dir {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            self.fileURL = dir?.appendingPathComponent("workspaces-v1.json")
        }
        loadWorkspaces()
    }

    var activeWorkspace: Workspace {
        if let found = workspaces.first(where: { $0.id == activeWorkspaceId }) {
            return found
        }
        if let defaultWs = workspaces.first(where: { $0.isDefault }) {
            return defaultWs
        }
        return workspaces.first ?? Self.builtInPresets[0]
    }

    // MARK: - Persistence & Schema Migration

    func loadWorkspaces() {
        var loadedBundle: WorkspaceExportBundle?

        // 1. Try primary file storage first, then UserDefaults fallback
        if let url = fileURL,
           let fileData = try? Data(contentsOf: url),
           let decoded = Self.decodeAndMigrateBundle(from: fileData) {
            loadedBundle = decoded
        } else if let udData = userDefaults.data(forKey: storageKey),
                  let decoded = Self.decodeAndMigrateBundle(from: udData) {
            loadedBundle = decoded
        }

        if let bundle = loadedBundle, !bundle.workspaces.isEmpty {
            var merged = bundle.workspaces.map { ws -> Workspace in
                var copy = ws
                copy.layout = ws.layout.normalized()
                return copy
            }

            // Non-destructive preset seeding: add any missing built-in presets without overwriting existing custom/edited workspaces
            let existingIds = Set(merged.map { $0.id })
            for preset in Self.builtInPresets where !existingIds.contains(preset.id) {
                merged.append(preset)
            }

            if !merged.contains(where: { $0.isDefault }), !merged.isEmpty {
                merged[0].isDefault = true
            }

            self.workspaces = merged

            let savedActiveId = userDefaults.string(forKey: activeWorkspaceKey) ?? bundle.activeWorkspaceId
            if let savedActiveId, merged.contains(where: { $0.id == savedActiveId }) {
                self.activeWorkspaceId = savedActiveId
            } else if let def = merged.first(where: { $0.isDefault }) {
                self.activeWorkspaceId = def.id
            } else {
                self.activeWorkspaceId = merged[0].id
            }
            saveWorkspaces()
        } else {
            self.workspaces = Self.builtInPresets
            self.activeWorkspaceId = Self.builtInPresets[0].id
            saveWorkspaces()
        }
    }

    func saveWorkspaces() {
        let bundle = WorkspaceExportBundle(
            schemaVersion: PadWorkspaceSchema.currentVersion,
            exportedAt: Date(),
            appVersion: "1.0",
            activeWorkspaceId: activeWorkspaceId,
            workspaces: workspaces
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(bundle) else { return }
        userDefaults.set(data, forKey: storageKey)
        userDefaults.set(activeWorkspaceId, forKey: activeWorkspaceKey)
        if let url = fileURL {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Supports decoding current `WorkspaceExportBundle`, single `Workspace`, or legacy `[Workspace]` array.
    static func decodeAndMigrateBundle(from data: Data) -> WorkspaceExportBundle? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let bundle = try? decoder.decode(WorkspaceExportBundle.self, from: data) {
            return bundle
        }

        // Fallback decoder without strict iso8601 date requirement
        let fallbackDecoder = JSONDecoder()
        if let bundle = try? fallbackDecoder.decode(WorkspaceExportBundle.self, from: data) {
            return bundle
        }

        // Legacy v0 migration: raw [Workspace] array
        if let array = try? fallbackDecoder.decode([Workspace].self, from: data), !array.isEmpty {
            return WorkspaceExportBundle(
                schemaVersion: PadWorkspaceSchema.currentVersion,
                activeWorkspaceId: array.first?.id,
                workspaces: array
            )
        }

        // Single Workspace JSON
        if let single = try? fallbackDecoder.decode(Workspace.self, from: data) {
            return WorkspaceExportBundle(
                schemaVersion: PadWorkspaceSchema.currentVersion,
                activeWorkspaceId: single.id,
                workspaces: [single]
            )
        }

        return nil
    }

    // MARK: - M5.1 Workspace CRUD Operations

    @discardableResult
    func createWorkspace(
        name: String,
        icon: String = "square.grid.2x2.fill",
        accentColor: ControlColor = .indigo,
        columns: Int = PadWorkspaceSchema.defaultColumns,
        rows: Int = PadWorkspaceSchema.defaultRows
    ) -> Workspace {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Workspace Baru" : trimmed
        let newWorkspace = Workspace(
            id: "custom.\(UUID().uuidString)",
            name: finalName,
            icon: icon,
            accentColor: accentColor,
            isPreset: false,
            isDefault: false,
            layout: WorkspaceLayout(columns: columns, rows: rows, items: []),
            settings: WorkspaceSettings()
        )
        workspaces.append(newWorkspace)
        activeWorkspaceId = newWorkspace.id
        saveWorkspaces()
        return newWorkspace
    }

    func updateWorkspaceMetadata(
        id: String,
        name: String,
        icon: String? = nil,
        accentColor: ControlColor? = nil,
        settings: WorkspaceSettings? = nil
    ) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            workspaces[idx].name = trimmed
        }
        if let icon {
            workspaces[idx].icon = icon
        }
        if let accentColor {
            workspaces[idx].accentColor = accentColor
        }
        if let settings {
            workspaces[idx].settings = settings
        }
        workspaces[idx].updatedAt = Date()
        saveWorkspaces()
    }

    @discardableResult
    func duplicateWorkspace(id: String, newName: String? = nil) -> Workspace? {
        guard let source = workspaces.first(where: { $0.id == id }) else { return nil }
        let duplicatedItems = source.layout.items.map { item -> ControlItem in
            var copy = item
            copy.id = UUID().uuidString
            return copy
        }
        let duplicate = Workspace(
            id: "custom.\(UUID().uuidString)",
            name: newName ?? "\(source.name) Copy",
            icon: source.icon,
            accentColor: source.accentColor,
            isPreset: false,
            isDefault: false,
            layout: WorkspaceLayout(
                columns: source.layout.columns,
                rows: source.layout.rows,
                items: duplicatedItems
            ),
            settings: source.settings
        )
        workspaces.append(duplicate)
        activeWorkspaceId = duplicate.id
        saveWorkspaces()
        return duplicate
    }

    @discardableResult
    func deleteWorkspace(id: String) -> Bool {
        guard workspaces.count > 1,
              let idx = workspaces.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let wasDefault = workspaces[idx].isDefault
        workspaces.remove(at: idx)

        if wasDefault, !workspaces.isEmpty {
            workspaces[0].isDefault = true
        }
        if activeWorkspaceId == id {
            activeWorkspaceId = (workspaces.first(where: { $0.isDefault }) ?? workspaces[0]).id
        }
        saveWorkspaces()
        return true
    }

    func switchWorkspace(to id: String) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        activeWorkspaceId = id
        saveWorkspaces()
    }

    func setDefaultWorkspace(id: String) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        for idx in workspaces.indices {
            workspaces[idx].isDefault = (workspaces[idx].id == id)
        }
        saveWorkspaces()
    }

    func resetPresetWorkspace(id: String) {
        guard let preset = Self.builtInPresets.first(where: { $0.id == id }),
              let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let keepDefault = workspaces[idx].isDefault
        var restored = preset
        restored.isDefault = keepDefault
        workspaces[idx] = restored
        saveWorkspaces()
    }

    // MARK: - M5.2 Layout Engine Operations

    @discardableResult
    func addControlItem(_ item: ControlItem, to workspaceId: String? = nil) -> Bool {
        let targetId = workspaceId ?? activeWorkspaceId
        guard let idx = workspaces.firstIndex(where: { $0.id == targetId }) else { return false }

        var layout = workspaces[idx].layout
        var newItem = item
        newItem.order = layout.items.count

        if layout.canPlace(newItem) {
            layout.items.append(newItem)
        } else if let pos = layout.firstAvailablePosition(for: newItem.size) {
            newItem.row = pos.row
            newItem.col = pos.col
            layout.items.append(newItem)
        } else if layout.rows < PadWorkspaceSchema.maxRows {
            layout.rows += 1
            if let pos = layout.firstAvailablePosition(for: newItem.size) {
                newItem.row = pos.row
                newItem.col = pos.col
                layout.items.append(newItem)
            } else {
                return false
            }
        } else {
            return false
        }

        workspaces[idx].layout = layout.normalized()
        workspaces[idx].updatedAt = Date()
        saveWorkspaces()
        return true
    }

    @discardableResult
    func updateControlItem(_ item: ControlItem, in workspaceId: String? = nil) -> Bool {
        let targetId = workspaceId ?? activeWorkspaceId
        guard let wsIdx = workspaces.firstIndex(where: { $0.id == targetId }),
              let itemIdx = workspaces[wsIdx].layout.items.firstIndex(where: { $0.id == item.id }) else {
            return false
        }

        var layout = workspaces[wsIdx].layout
        if layout.canPlace(item, excludingItemId: item.id) {
            layout.items[itemIdx] = item
        } else if let pos = layout.firstAvailablePosition(for: item.size, excludingItemId: item.id) {
            var adjusted = item
            adjusted.row = pos.row
            adjusted.col = pos.col
            layout.items[itemIdx] = adjusted
        } else {
            return false
        }

        workspaces[wsIdx].layout = layout.normalized()
        workspaces[wsIdx].updatedAt = Date()
        saveWorkspaces()
        return true
    }

    func removeControlItem(itemId: String, from workspaceId: String? = nil) {
        let targetId = workspaceId ?? activeWorkspaceId
        guard let wsIdx = workspaces.firstIndex(where: { $0.id == targetId }) else { return }
        workspaces[wsIdx].layout.items.removeAll { $0.id == itemId }
        workspaces[wsIdx].layout = workspaces[wsIdx].layout.normalized()
        workspaces[wsIdx].updatedAt = Date()
        saveWorkspaces()
    }

    /// Moves an item to `(targetRow, targetCol)` if free, or swaps with a single occupying item if collision-free.
    @discardableResult
    func moveControlItem(
        itemId: String,
        toRow targetRow: Int,
        toCol targetCol: Int,
        in workspaceId: String? = nil
    ) -> Bool {
        let targetId = workspaceId ?? activeWorkspaceId
        guard let wsIdx = workspaces.firstIndex(where: { $0.id == targetId }),
              let sourceIdx = workspaces[wsIdx].layout.items.firstIndex(where: { $0.id == itemId }) else {
            return false
        }

        var layout = workspaces[wsIdx].layout
        let sourceItem = layout.items[sourceIdx]

        var movedSource = sourceItem
        movedSource.row = max(0, min(layout.rows - sourceItem.size.rowSpan, targetRow))
        movedSource.col = max(0, min(layout.columns - sourceItem.size.colSpan, targetCol))

        // Case 1: direct placement has no collision
        if layout.canPlace(movedSource, excludingItemId: sourceItem.id) {
            layout.items[sourceIdx] = movedSource
            workspaces[wsIdx].layout = layout
            workspaces[wsIdx].updatedAt = Date()
            saveWorkspaces()
            return true
        }

        // Case 2: swap with single occupying item at destination cell
        let targetCells = movedSource.occupiedCells()
        let collidingIndices = layout.items.indices.filter { idx in
            idx != sourceIdx && !layout.items[idx].occupiedCells().isDisjoint(with: targetCells)
        }

        if collidingIndices.count == 1, let otherIdx = collidingIndices.first {
            var otherItem = layout.items[otherIdx]
            otherItem.row = sourceItem.row
            otherItem.col = sourceItem.col
            let tempOrder = movedSource.order
            movedSource.order = otherItem.order
            otherItem.order = tempOrder

            var testLayout = layout
            testLayout.items[sourceIdx] = movedSource
            testLayout.items[otherIdx] = otherItem

            if testLayout.validateNoCollisions() {
                workspaces[wsIdx].layout = testLayout
                workspaces[wsIdx].updatedAt = Date()
                saveWorkspaces()
                return true
            }
        }

        return false
    }

    func resizeGrid(columns: Int, rows: Int, in workspaceId: String? = nil) {
        let targetId = workspaceId ?? activeWorkspaceId
        guard let wsIdx = workspaces.firstIndex(where: { $0.id == targetId }) else { return }
        var layout = workspaces[wsIdx].layout
        layout.columns = max(PadWorkspaceSchema.minColumns, min(PadWorkspaceSchema.maxColumns, columns))
        layout.rows = max(PadWorkspaceSchema.minRows, min(PadWorkspaceSchema.maxRows, rows))
        workspaces[wsIdx].layout = layout.normalized()
        workspaces[wsIdx].updatedAt = Date()
        saveWorkspaces()
    }

    // MARK: - M5.4 Import, Export, Backup & Validation

    func exportWorkspaceData(id: String) throws -> Data {
        guard let ws = workspaces.first(where: { $0.id == id }) else {
            throw WorkspaceImportError.noWorkspacesFound
        }
        let bundle = WorkspaceExportBundle(
            schemaVersion: PadWorkspaceSchema.currentVersion,
            exportedAt: Date(),
            appVersion: "1.0",
            activeWorkspaceId: ws.id,
            workspaces: [ws]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    func exportAllWorkspacesData() throws -> Data {
        let bundle = WorkspaceExportBundle(
            schemaVersion: PadWorkspaceSchema.currentVersion,
            exportedAt: Date(),
            appVersion: "1.0",
            activeWorkspaceId: activeWorkspaceId,
            workspaces: workspaces
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    /// Validates raw JSON data, checks schema compatibility, normalizes any out-of-bounds/colliding items,
    /// and detects conflicts with existing workspaces before applying changes.
    func validateImportData(_ data: Data) -> Result<WorkspaceImportPreview, WorkspaceImportError> {
        guard !data.isEmpty else {
            return .failure(.emptyPayload)
        }

        // Inspect raw JSON object first to check schemaVersion explicitly
        if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rawVersion = jsonObj["schemaVersion"] as? Int {
            if rawVersion < PadWorkspaceSchema.minimumSupportedVersion || rawVersion > PadWorkspaceSchema.currentVersion {
                return .failure(.unsupportedSchemaVersion(rawVersion))
            }
        }

        guard var bundle = Self.decodeAndMigrateBundle(from: data) else {
            return .failure(.invalidJSON("Struktur JSON tidak sesuai format Workspace EvoPad."))
        }

        if bundle.schemaVersion < PadWorkspaceSchema.minimumSupportedVersion ||
            bundle.schemaVersion > PadWorkspaceSchema.currentVersion {
            return .failure(.unsupportedSchemaVersion(bundle.schemaVersion))
        }

        guard !bundle.workspaces.isEmpty else {
            return .failure(.noWorkspacesFound)
        }

        var hadCollisionRepairs = false
        var sanitizedWorkspaces: [Workspace] = []

        for var ws in bundle.workspaces {
            let trimmedName = ws.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty, !ws.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.invalidWorkspaceData("Workspace memiliki ID atau nama kosong."))
            }
            ws.name = trimmedName

            for item in ws.layout.items {
                if item.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    item.action.actionReferenceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .failure(.invalidWorkspaceData("Tombol dalam '\(ws.name)' memiliki label atau action kosong."))
                }
            }

            if !ws.layout.validateNoCollisions() {
                hadCollisionRepairs = true
            }
            ws.layout = ws.layout.normalized()
            sanitizedWorkspaces.append(ws)
        }

        bundle.workspaces = sanitizedWorkspaces

        let existingIds = Set(workspaces.map { $0.id })
        let existingNames = Set(workspaces.map { $0.name.lowercased() })
        let conflicts = sanitizedWorkspaces.filter {
            existingIds.contains($0.id) || existingNames.contains($0.name.lowercased())
        }.map { $0.name }

        return .success(
            WorkspaceImportPreview(
                bundle: bundle,
                conflictingWorkspaceNames: conflicts,
                hadCollisionRepairs: hadCollisionRepairs
            )
        )
    }

    /// Applies a validated import preview using the chosen conflict policy.
    /// Never overwrites existing workspaces unless `.overwriteApproved` is explicitly specified.
    @discardableResult
    func applyImport(
        _ preview: WorkspaceImportPreview,
        policy: WorkspaceImportConflictPolicy = .keepBoth
    ) -> Int {
        var importedCount = 0

        for var incoming in preview.bundle.workspaces {
            incoming.layout = incoming.layout.normalized()
            incoming.isDefault = false

            let matchingIdx = workspaces.firstIndex {
                $0.id == incoming.id || $0.name.lowercased() == incoming.name.lowercased()
            }

            if let idx = matchingIdx {
                switch policy {
                case .skipConflicting:
                    continue
                case .overwriteApproved:
                    let preserveDefault = workspaces[idx].isDefault
                    incoming.id = workspaces[idx].id
                    incoming.isDefault = preserveDefault
                    incoming.updatedAt = Date()
                    workspaces[idx] = incoming
                    importedCount += 1
                case .keepBoth:
                    incoming.id = "custom.\(UUID().uuidString)"
                    incoming.isPreset = false
                    incoming.name = uniqueImportedName(base: incoming.name)
                    incoming.updatedAt = Date()
                    workspaces.append(incoming)
                    importedCount += 1
                }
            } else {
                workspaces.append(incoming)
                importedCount += 1
            }
        }

        if let lastImported = workspaces.last, importedCount > 0 {
            activeWorkspaceId = lastImported.id
        }
        saveWorkspaces()
        return importedCount
    }

    private func uniqueImportedName(base: String) -> String {
        let existingNames = Set(workspaces.map { $0.name.lowercased() })
        let candidate = "\(base) (Imported)"
        if !existingNames.contains(candidate.lowercased()) {
            return candidate
        }
        var counter = 2
        while existingNames.contains("\(base) (Imported \(counter))".lowercased()) {
            counter += 1
        }
        return "\(base) (Imported \(counter))"
    }

    // MARK: - 5 Built-in Presets (M5.1)

    static var builtInPresets: [Workspace] {
        [
            generalPreset,
            codingPreset,
            designPreset,
            officePreset,
            mediaPreset
        ]
    }

    static var generalPreset: Workspace {
        Workspace(
            id: "preset.general",
            name: "General",
            icon: "sparkles.rectangle.stack.fill",
            accentColor: .indigo,
            isPreset: true,
            isDefault: true,
            layout: WorkspaceLayout(
                columns: 4,
                rows: 2,
                items: [
                    ControlItem(id: "gen.copy", label: "Copy", icon: "doc.on.doc", color: .indigo, category: .shortcut, row: 0, col: 0, size: .small, order: 0, action: .standardShortcut(.copy)),
                    ControlItem(id: "gen.paste", label: "Paste", icon: "doc.on.clipboard", color: .blue, category: .shortcut, row: 0, col: 1, size: .small, order: 1, action: .standardShortcut(.paste)),
                    ControlItem(id: "gen.undo", label: "Undo", icon: "arrow.uturn.backward", color: .cyan, category: .shortcut, row: 0, col: 2, size: .small, order: 2, action: .standardShortcut(.undo)),
                    ControlItem(id: "gen.spotlight", label: "Spotlight", icon: "magnifyingglass", color: .purple, category: .navigation, row: 0, col: 3, size: .small, order: 3, action: .standardShortcut(.spotlight)),
                    ControlItem(id: "gen.mission", label: "Mission Ctrl", icon: "rectangle.3.group", color: .teal, category: .navigation, row: 1, col: 0, size: .small, order: 4, action: .standardShortcut(.missionControl)),
                    ControlItem(id: "gen.play", label: "Play / Pause", icon: "playpause.fill", color: .green, category: .media, row: 1, col: 1, size: .small, order: 5, action: .media(.playPause)),
                    ControlItem(id: "gen.shot", label: "Screenshot", icon: "camera.viewfinder", color: .orange, category: .system, row: 1, col: 2, size: .small, order: 6, action: .system(.screenshot)),
                    ControlItem(id: "gen.switch", label: "App Switch", icon: "rectangle.stack", color: .pink, category: .navigation, row: 1, col: 3, size: .small, order: 7, action: .standardShortcut(.commandTab))
                ]
            )
        )
    }

    static var codingPreset: Workspace {
        Workspace(
            id: "preset.coding",
            name: "Coding",
            icon: "chevron.left.forwardslash.chevron.right",
            accentColor: .blue,
            isPreset: true,
            isDefault: false,
            layout: WorkspaceLayout(
                columns: 4,
                rows: 2,
                items: [
                    ControlItem(id: "code.terminal", label: "Terminal", icon: "terminal.fill", color: .blue, category: .macro, row: 0, col: 0, size: .small, order: 0, action: .macro(id: "preset.launchTerminal")),
                    ControlItem(id: "code.dupline", label: "Duplikat Baris", icon: "plus.square.on.square", color: .indigo, category: .macro, row: 0, col: 1, size: .small, order: 1, action: .macro(id: "preset.duplicateLine")),
                    ControlItem(id: "code.comment", label: "Comment", icon: "text.bubble", color: .teal, category: .shortcut, row: 0, col: 2, size: .small, order: 2, action: .customShortcut(keyCode: 44, modifiers: [.cmd], id: "chord.cmd.slash")),
                    ControlItem(id: "code.build", label: "Build (⌘B)", icon: "hammer.fill", color: .green, category: .shortcut, row: 0, col: 3, size: .small, order: 3, action: .customShortcut(keyCode: 11, modifiers: [.cmd], id: "chord.cmd.b")),
                    ControlItem(id: "code.copyall", label: "Salin Semua", icon: "doc.on.doc.fill", color: .cyan, category: .macro, row: 1, col: 0, size: .small, order: 4, action: .macro(id: "preset.copyAll")),
                    ControlItem(id: "code.undo", label: "Undo", icon: "arrow.uturn.backward", color: .orange, category: .shortcut, row: 1, col: 1, size: .small, order: 5, action: .standardShortcut(.undo)),
                    ControlItem(id: "code.redo", label: "Redo", icon: "arrow.uturn.forward", color: .orange, category: .shortcut, row: 1, col: 2, size: .small, order: 6, action: .standardShortcut(.redo)),
                    ControlItem(id: "code.spotlight", label: "Quick Open", icon: "magnifyingglass", color: .purple, category: .navigation, row: 1, col: 3, size: .small, order: 7, action: .standardShortcut(.spotlight))
                ]
            )
        )
    }

    static var designPreset: Workspace {
        Workspace(
            id: "preset.design",
            name: "Design",
            icon: "paintbrush.pointed.fill",
            accentColor: .purple,
            isPreset: true,
            isDefault: false,
            layout: WorkspaceLayout(
                columns: 4,
                rows: 2,
                items: [
                    ControlItem(id: "des.undo", label: "Undo", icon: "arrow.uturn.backward", color: .purple, category: .shortcut, row: 0, col: 0, size: .small, order: 0, action: .standardShortcut(.undo)),
                    ControlItem(id: "des.redo", label: "Redo", icon: "arrow.uturn.forward", color: .pink, category: .shortcut, row: 0, col: 1, size: .small, order: 1, action: .standardShortcut(.redo)),
                    ControlItem(id: "des.zoomin", label: "Zoom In", icon: "plus.magnifyingglass", color: .cyan, category: .shortcut, row: 0, col: 2, size: .small, order: 2, action: .customShortcut(keyCode: 24, modifiers: [.cmd], id: "chord.cmd.plus")),
                    ControlItem(id: "des.zoomout", label: "Zoom Out", icon: "minus.magnifyingglass", color: .blue, category: .shortcut, row: 0, col: 3, size: .small, order: 3, action: .customShortcut(keyCode: 27, modifiers: [.cmd], id: "chord.cmd.minus")),
                    ControlItem(id: "des.copy", label: "Copy", icon: "doc.on.doc", color: .indigo, category: .shortcut, row: 1, col: 0, size: .small, order: 4, action: .standardShortcut(.copy)),
                    ControlItem(id: "des.paste", label: "Paste", icon: "doc.on.clipboard", color: .teal, category: .shortcut, row: 1, col: 1, size: .small, order: 5, action: .standardShortcut(.paste)),
                    ControlItem(id: "des.fit", label: "Reset Zoom", icon: "1.magnifyingglass", color: .green, category: .shortcut, row: 1, col: 2, size: .small, order: 6, action: .customShortcut(keyCode: 29, modifiers: [.cmd], id: "chord.cmd.0")),
                    ControlItem(id: "des.shot", label: "Capture", icon: "camera.viewfinder", color: .orange, category: .system, row: 1, col: 3, size: .small, order: 7, action: .system(.screenshot))
                ]
            )
        )
    }

    static var officePreset: Workspace {
        Workspace(
            id: "preset.office",
            name: "Office",
            icon: "doc.text.fill",
            accentColor: .teal,
            isPreset: true,
            isDefault: false,
            layout: WorkspaceLayout(
                columns: 4,
                rows: 2,
                items: [
                    ControlItem(id: "off.copy", label: "Copy", icon: "doc.on.doc", color: .teal, category: .shortcut, row: 0, col: 0, size: .small, order: 0, action: .standardShortcut(.copy)),
                    ControlItem(id: "off.paste", label: "Paste", icon: "doc.on.clipboard", color: .blue, category: .shortcut, row: 0, col: 1, size: .small, order: 1, action: .standardShortcut(.paste)),
                    ControlItem(id: "off.cut", label: "Cut", icon: "scissors", color: .orange, category: .shortcut, row: 0, col: 2, size: .small, order: 2, action: .standardShortcut(.cut)),
                    ControlItem(id: "off.selall", label: "Select All", icon: "selection.pin.in.out", color: .indigo, category: .shortcut, row: 0, col: 3, size: .small, order: 3, action: .standardShortcut(.selectAll)),
                    ControlItem(id: "off.copyall", label: "Salin Semua", icon: "doc.on.doc.fill", color: .cyan, category: .macro, row: 1, col: 0, size: .small, order: 4, action: .macro(id: "preset.copyAll")),
                    ControlItem(id: "off.newtab", label: "Tab Baru", icon: "plus.square.fill", color: .green, category: .macro, row: 1, col: 1, size: .small, order: 5, action: .macro(id: "preset.newTab")),
                    ControlItem(id: "off.switch", label: "App Switch", icon: "rectangle.stack", color: .purple, category: .navigation, row: 1, col: 2, size: .small, order: 6, action: .standardShortcut(.commandTab)),
                    ControlItem(id: "off.lock", label: "Lock Mac", icon: "lock.fill", color: .red, category: .system, row: 1, col: 3, size: .small, order: 7, action: .system(.lockScreen))
                ]
            )
        )
    }

    static var mediaPreset: Workspace {
        Workspace(
            id: "preset.media",
            name: "Media",
            icon: "play.tv.fill",
            accentColor: .pink,
            isPreset: true,
            isDefault: false,
            layout: WorkspaceLayout(
                columns: 4,
                rows: 2,
                items: [
                    ControlItem(id: "med.prev", label: "Prev", icon: "backward.fill", color: .purple, category: .media, row: 0, col: 0, size: .small, order: 0, action: .media(.previousTrack)),
                    ControlItem(id: "med.play", label: "Play / Pause", icon: "playpause.fill", color: .pink, category: .media, row: 0, col: 1, size: .wide, order: 1, action: .media(.playPause)),
                    ControlItem(id: "med.next", label: "Next", icon: "forward.fill", color: .purple, category: .media, row: 0, col: 3, size: .small, order: 2, action: .media(.nextTrack)),
                    ControlItem(id: "med.voldown", label: "Vol -", icon: "speaker.wave.1.fill", color: .blue, category: .media, row: 1, col: 0, size: .small, order: 3, action: .media(.volumeDown)),
                    ControlItem(id: "med.volup", label: "Vol +", icon: "speaker.wave.3.fill", color: .cyan, category: .media, row: 1, col: 1, size: .small, order: 4, action: .media(.volumeUp)),
                    ControlItem(id: "med.mute", label: "Mute", icon: "speaker.slash.fill", color: .orange, category: .media, row: 1, col: 2, size: .small, order: 5, action: .media(.mute)),
                    ControlItem(id: "med.sleep", label: "Sleep Mac", icon: "moon.fill", color: .indigo, category: .system, row: 1, col: 3, size: .small, order: 6, action: .system(.sleep))
                ]
            )
        )
    }

    // MARK: - Automated Self-Check Suite (M5.1 – M5.4 Verification)

    /// Runs deterministic verification assertions covering Workspace CRUD, Persistence,
    /// Layout Collision Engine, Action Reference Resolution, Import/Export Validation, and Schema Migration.
    @discardableResult
    static func runSelfChecks() -> [String] {
        var passed: [String] = []
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("evopad-m5-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test-workspaces.json")
        let suiteName = "id.evonex.evopad.test.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        // 1. M5.1 Workspace CRUD & Presets
        let store = PadWorkspaceStore(
            userDefaults: testDefaults,
            storageKey: "ws.v1",
            activeWorkspaceKey: "active.v1",
            customFileURL: fileURL
        )
        assert(store.workspaces.count == 5, "Expected 5 built-in presets")
        assert(store.activeWorkspace.id == "preset.general", "Default active workspace must be General")

        let custom = store.createWorkspace(name: "Video Editing", icon: "film", accentColor: .orange, columns: 4, rows: 3)
        assert(store.workspaces.count == 6, "Custom workspace should be added")
        assert(store.activeWorkspaceId == custom.id, "New workspace becomes active")

        store.updateWorkspaceMetadata(id: custom.id, name: "Pro Video", accentColor: .red)
        assert(store.activeWorkspace.name == "Pro Video", "Workspace rename must persist")

        let dup = store.duplicateWorkspace(id: custom.id)
        assert(dup != nil && store.workspaces.count == 7, "Workspace duplication must succeed")

        store.setDefaultWorkspace(id: custom.id)
        assert(store.workspaces.first(where: { $0.id == custom.id })?.isDefault == true, "Default flag must update")

        // Reload persistence & verify custom workspace survives preset seeding
        let reloadedStore = PadWorkspaceStore(
            userDefaults: testDefaults,
            storageKey: "ws.v1",
            activeWorkspaceKey: "active.v1",
            customFileURL: fileURL
        )
        assert(reloadedStore.workspaces.count == 7, "Reloaded store must retain custom workspaces alongside presets")
        assert(reloadedStore.workspaces.contains(where: { $0.name == "Pro Video" }), "Custom workspace must not be lost")

        if let dupId = dup?.id {
            let deleted = reloadedStore.deleteWorkspace(id: dupId)
            assert(deleted && reloadedStore.workspaces.count == 6, "Delete workspace must succeed")
        }
        passed.append("M5.1 Workspace CRUD, Presets & Persistence: PASS")

        // 2. M5.2 Layout Grid & Collision Detection
        reloadedStore.switchWorkspace(to: custom.id)
        let btn1 = ControlItem(id: "b1", label: "Cut", icon: "scissors", color: .blue, category: .shortcut, row: 0, col: 0, size: .wide, action: .standardShortcut(.cut))
        let btn2 = ControlItem(id: "b2", label: "Copy", icon: "doc.on.doc", color: .indigo, category: .shortcut, row: 0, col: 0, size: .small, action: .standardShortcut(.copy))
        assert(reloadedStore.addControlItem(btn1, to: custom.id), "First wide button placed at (0,0)-(0,1)")
        assert(reloadedStore.addControlItem(btn2, to: custom.id), "Colliding button auto-placed at next free cell (0,2)")
        assert(reloadedStore.activeWorkspace.layout.validateNoCollisions(), "Layout must have zero collisions")

        let moved = reloadedStore.moveControlItem(itemId: "b2", toRow: 1, toCol: 1, in: custom.id)
        assert(moved && reloadedStore.activeWorkspace.layout.validateNoCollisions(), "Move to empty cell must succeed without collision")
        passed.append("M5.2 Layout Grid & Collision Prevention: PASS")

        // 3. M5.3 Action Reference & Customization
        let customChord = ControlAction.customShortcut(keyCode: 11, modifiers: [.cmd, .shift])
        assert(customChord.badgeText.contains("⌘") && customChord.badgeText.contains("B"), "Custom chord badge must render")
        passed.append("M5.3 Customization & Action Reference: PASS")

        // 4. M5.4 Export, Import, Validation, Corrupt & Conflict Handling
        let exportedData = try! reloadedStore.exportWorkspaceData(id: custom.id)
        let previewResult = reloadedStore.validateImportData(exportedData)
        guard case .success(let preview) = previewResult else {
            assertionFailure("Exported JSON must validate")
            return passed
        }
        assert(preview.hasConflicts, "Importing existing workspace must flag conflict")
        let countBefore = reloadedStore.workspaces.count
        reloadedStore.applyImport(preview, policy: .keepBoth)
        assert(reloadedStore.workspaces.count == countBefore + 1, "keepBoth policy must add copy without overwriting")

        // Corrupt JSON check
        let corruptResult = reloadedStore.validateImportData(Data("{bad json".utf8))
        if case .failure(.invalidJSON) = corruptResult {} else {
            assertionFailure("Corrupt JSON must be rejected")
        }

        // Incompatible schema version check
        let futureJSON = Data(#"{"schemaVersion": 99, "exportedAt": "2026-11-02T00:00:00Z", "appVersion": "2.0", "workspaces": []}"#.utf8)
        let schemaResult = reloadedStore.validateImportData(futureJSON)
        if case .failure(.unsupportedSchemaVersion(99)) = schemaResult {} else {
            assertionFailure("Incompatible schema version must be rejected")
        }

        // Legacy v0 migration check (raw [Workspace] array without envelope)
        let legacyArrayData = try! JSONEncoder().encode([Self.generalPreset])
        let migrated = Self.decodeAndMigrateBundle(from: legacyArrayData)
        assert(migrated?.workspaces.count == 1 && migrated?.schemaVersion == PadWorkspaceSchema.currentVersion, "Legacy array must migrate cleanly to current schema")
        passed.append("M5.4 Import/Export, Schema Validation & Migration: PASS")

        return passed
    }
}

