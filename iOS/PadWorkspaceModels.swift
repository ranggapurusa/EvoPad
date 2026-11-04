import Foundation
import SwiftUI

// MARK: - Schema Version & Constants

enum PadWorkspaceSchema {
    static let currentVersion = 1
    static let minimumSupportedVersion = 1
    static let defaultColumns = 4
    static let defaultRows = 3
    static let minColumns = 3
    static let maxColumns = 6
    static let minRows = 2
    static let maxRows = 6
}

// MARK: - Visual Customization Enums (M5.3)

enum ControlColor: String, Codable, CaseIterable, Identifiable, Equatable {
    case indigo
    case blue
    case cyan
    case teal
    case green
    case orange
    case red
    case pink
    case purple
    case slate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .indigo: return "Indigo"
        case .blue: return "Biru"
        case .cyan: return "Cyan"
        case .teal: return "Teal"
        case .green: return "Hijau"
        case .orange: return "Oranye"
        case .red: return "Merah"
        case .pink: return "Pink"
        case .purple: return "Ungu"
        case .slate: return "Abu-abu"
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .indigo: return .indigo
        case .blue: return .blue
        case .cyan: return .cyan
        case .teal: return .teal
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .purple: return .purple
        case .slate: return .gray
        }
    }
}

enum ControlCategory: String, Codable, CaseIterable, Identifiable, Equatable {
    case shortcut
    case macro
    case media
    case system
    case navigation
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortcut: return "Shortcut"
        case .macro: return "Macro"
        case .media: return "Media"
        case .system: return "System"
        case .navigation: return "Navigasi"
        case .custom: return "Custom"
        }
    }

    var symbol: String {
        switch self {
        case .shortcut: return "command"
        case .macro: return "sparkles.rectangle.stack"
        case .media: return "play.circle"
        case .system: return "macwindow"
        case .navigation: return "arrow.up.and.down.and.arrow.left.and.right"
        case .custom: return "slider.horizontal.3"
        }
    }
}

enum ControlSize: String, Codable, CaseIterable, Identifiable, Equatable {
    case small   // 1x1 cell
    case wide    // 2x1 cells
    case large   // 2x2 cells

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "1×1 Standar"
        case .wide: return "2×1 Lebar"
        case .large: return "2×2 Besar"
        }
    }

    var colSpan: Int {
        switch self {
        case .small: return 1
        case .wide, .large: return 2
        }
    }

    var rowSpan: Int {
        switch self {
        case .small, .wide: return 1
        case .large: return 2
        }
    }
}

// MARK: - Grid Coordinate & Collision Helpers (M5.2)

struct GridCell: Hashable, Codable, Equatable {
    let row: Int
    let col: Int
}

// MARK: - ControlAction (M5.3 Stable Action Reference)

enum ControlActionKind: String, Codable, CaseIterable, Identifiable, Equatable {
    case standardShortcut
    case customShortcut
    case macro
    case media
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standardShortcut: return "Shortcut Standar"
        case .customShortcut: return "Custom Shortcut Chord"
        case .macro: return "Macro Sequence"
        case .media: return "Media Control"
        case .system: return "System Control"
        }
    }
}

/// References an executable action by a stable identifier without duplicating Shortcut or Macro engine logic.
struct ControlAction: Codable, Equatable {
    var kind: ControlActionKind
    /// Stable ID referencing `PadStandardShortcut.rawValue`, `PadMacroDefinition.id`,
    /// `PadMediaControlKey.rawValue`, `PadSystemControlAction.rawValue`, or custom chord identifier.
    var actionReferenceId: String
    var customKeyCode: UInt16?
    var customModifiers: [PadModifierFlagV2]?
    var targetApp: String?

    init(
        kind: ControlActionKind,
        actionReferenceId: String,
        customKeyCode: UInt16? = nil,
        customModifiers: [PadModifierFlagV2]? = nil,
        targetApp: String? = nil
    ) {
        self.kind = kind
        self.actionReferenceId = actionReferenceId
        self.customKeyCode = customKeyCode
        self.customModifiers = customModifiers
        self.targetApp = targetApp
    }

    static func standardShortcut(_ shortcut: PadStandardShortcut) -> ControlAction {
        ControlAction(kind: .standardShortcut, actionReferenceId: shortcut.rawValue)
    }

    static func customShortcut(keyCode: UInt16, modifiers: [PadModifierFlagV2], id: String? = nil) -> ControlAction {
        let modString = modifiers.map { $0.rawValue }.sorted().joined(separator: "+")
        let refId = id ?? "chord.\(modString).\(keyCode)"
        return ControlAction(
            kind: .customShortcut,
            actionReferenceId: refId,
            customKeyCode: keyCode,
            customModifiers: modifiers
        )
    }

    static func macro(id: String) -> ControlAction {
        ControlAction(kind: .macro, actionReferenceId: id)
    }

    static func media(_ key: PadMediaControlKey) -> ControlAction {
        ControlAction(kind: .media, actionReferenceId: key.rawValue)
    }

    static func system(_ action: PadSystemControlAction, targetApp: String? = nil) -> ControlAction {
        ControlAction(kind: .system, actionReferenceId: action.rawValue, targetApp: targetApp)
    }

    var badgeText: String {
        switch kind {
        case .standardShortcut:
            return PadStandardShortcut(rawValue: actionReferenceId)?.chordDescription ?? "Shortcut"
        case .customShortcut:
            let mods = (customModifiers ?? []).map { mod -> String in
                switch mod {
                case .cmd: return "⌘"
                case .shift: return "⇧"
                case .alt: return "⌥"
                case .ctrl: return "⌃"
                case .fn: return "fn"
                }
            }.joined()
            let keyLabel = Self.keyName(for: customKeyCode ?? 0)
            return "\(mods)\(keyLabel)"
        case .macro:
            return "MACRO"
        case .media:
            return "MEDIA"
        case .system:
            if actionReferenceId == PadSystemControlAction.launchApp.rawValue,
               let app = targetApp, !app.isEmpty {
                return app.components(separatedBy: ".").last ?? "APP"
            }
            return "SYSTEM"
        }
    }

    static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "⏎"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 109: return "F10"
        case 111: return "F12"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key\(keyCode)"
        }
    }
}

// MARK: - ControlItem (M5.2 & M5.3)

struct ControlItem: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var icon: String
    var color: ControlColor
    var category: ControlCategory
    var row: Int
    var col: Int
    var size: ControlSize
    var order: Int
    var action: ControlAction

    init(
        id: String = UUID().uuidString,
        label: String,
        icon: String,
        color: ControlColor,
        category: ControlCategory,
        row: Int,
        col: Int,
        size: ControlSize = .small,
        order: Int = 0,
        action: ControlAction
    ) {
        self.id = id
        self.label = label
        self.icon = icon
        self.color = color
        self.category = category
        self.row = row
        self.col = col
        self.size = size
        self.order = order
        self.action = action
    }

    func occupiedCells() -> Set<GridCell> {
        var cells = Set<GridCell>()
        for r in row..<(row + size.rowSpan) {
            for c in col..<(col + size.colSpan) {
                cells.insert(GridCell(row: r, col: c))
            }
        }
        return cells
    }
}

// MARK: - WorkspaceLayout (M5.2 Grid & Collision Engine)

struct WorkspaceLayout: Codable, Equatable {
    var columns: Int
    var rows: Int
    var items: [ControlItem]

    init(
        columns: Int = PadWorkspaceSchema.defaultColumns,
        rows: Int = PadWorkspaceSchema.defaultRows,
        items: [ControlItem] = []
    ) {
        self.columns = max(PadWorkspaceSchema.minColumns, min(PadWorkspaceSchema.maxColumns, columns))
        self.rows = max(PadWorkspaceSchema.minRows, min(PadWorkspaceSchema.maxRows, rows))
        self.items = items
    }

    /// Returns all occupied grid cells, optionally excluding a specific item by ID.
    func occupiedCells(excludingItemId: String? = nil) -> Set<GridCell> {
        var result = Set<GridCell>()
        for item in items where item.id != excludingItemId {
            result.formUnion(item.occupiedCells())
        }
        return result
    }

    /// Checks whether a candidate item fits within bounds and does not collide with any existing item.
    func canPlace(_ candidate: ControlItem, excludingItemId: String? = nil) -> Bool {
        guard candidate.row >= 0,
              candidate.col >= 0,
              candidate.row + candidate.size.rowSpan <= rows,
              candidate.col + candidate.size.colSpan <= columns else {
            return false
        }
        let existing = occupiedCells(excludingItemId: excludingItemId ?? candidate.id)
        return existing.isDisjoint(with: candidate.occupiedCells())
    }

    /// Validates that no two items in the layout overlap or exceed grid bounds.
    func validateNoCollisions() -> Bool {
        var seen = Set<GridCell>()
        for item in items {
            guard item.row >= 0,
                  item.col >= 0,
                  item.row + item.size.rowSpan <= rows,
                  item.col + item.size.colSpan <= columns else {
                return false
            }
            let cells = item.occupiedCells()
            if !seen.isDisjoint(with: cells) {
                return false
            }
            seen.formUnion(cells)
        }
        return true
    }

    /// Finds the first available (row, col) that can accommodate the given control size.
    func firstAvailablePosition(for size: ControlSize, excludingItemId: String? = nil) -> (row: Int, col: Int)? {
        let occupied = occupiedCells(excludingItemId: excludingItemId)
        for r in 0..<rows {
            for c in 0..<columns {
                guard r + size.rowSpan <= rows, c + size.colSpan <= columns else { continue }
                var fits = true
                for dr in 0..<size.rowSpan {
                    for dc in 0..<size.colSpan {
                        if occupied.contains(GridCell(row: r + dr, col: c + dc)) {
                            fits = false
                            break
                        }
                    }
                    if !fits { break }
                }
                if fits {
                    return (r, c)
                }
            }
        }
        return nil
    }

    /// Returns a collision-free copy of this layout, expanding rows if needed.
    func normalized() -> WorkspaceLayout {
        var result = WorkspaceLayout(columns: columns, rows: rows, items: [])
        let sorted = items.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            if lhs.row != rhs.row { return lhs.row < rhs.row }
            return lhs.col < rhs.col
        }

        for (index, var item) in sorted.enumerated() {
            item.order = index
            // Clamp size if wider than columns
            if item.size.colSpan > result.columns {
                item.size = .small
            }
            if result.canPlace(item) {
                result.items.append(item)
            } else if let pos = result.firstAvailablePosition(for: item.size) {
                item.row = pos.row
                item.col = pos.col
                result.items.append(item)
            } else if result.rows < PadWorkspaceSchema.maxRows {
                result.rows += 1
                if let pos = result.firstAvailablePosition(for: item.size) {
                    item.row = pos.row
                    item.col = pos.col
                    result.items.append(item)
                } else {
                    item.size = .small
                    if let posSmall = result.firstAvailablePosition(for: .small) {
                        item.row = posSmall.row
                        item.col = posSmall.col
                        result.items.append(item)
                    }
                }
            }
        }
        return result
    }
}

// MARK: - WorkspaceSettings & Workspace (M5.1)

struct WorkspaceSettings: Codable, Equatable {
    var hapticFeedback: Bool
    var showShortcutSubtitles: Bool
    var oneHandedCompactMode: Bool
    var confirmDestructiveSystemActions: Bool

    init(
        hapticFeedback: Bool = true,
        showShortcutSubtitles: Bool = true,
        oneHandedCompactMode: Bool = true,
        confirmDestructiveSystemActions: Bool = true
    ) {
        self.hapticFeedback = hapticFeedback
        self.showShortcutSubtitles = showShortcutSubtitles
        self.oneHandedCompactMode = oneHandedCompactMode
        self.confirmDestructiveSystemActions = confirmDestructiveSystemActions
    }
}

struct Workspace: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var icon: String
    var accentColor: ControlColor
    var isPreset: Bool
    var isDefault: Bool
    var presetVersion: Int
    var layout: WorkspaceLayout
    var settings: WorkspaceSettings
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        icon: String = "square.grid.2x2.fill",
        accentColor: ControlColor = .indigo,
        isPreset: Bool = false,
        isDefault: Bool = false,
        presetVersion: Int = 1,
        layout: WorkspaceLayout = WorkspaceLayout(),
        settings: WorkspaceSettings = WorkspaceSettings(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.accentColor = accentColor
        self.isPreset = isPreset
        self.isDefault = isDefault
        self.presetVersion = presetVersion
        self.layout = layout.normalized()
        self.settings = settings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Versioned Storage & Export Envelope (M5.4)

struct WorkspaceExportBundle: Codable, Equatable {
    var schemaVersion: Int
    var exportedAt: Date
    var appVersion: String
    var activeWorkspaceId: String?
    var workspaces: [Workspace]

    init(
        schemaVersion: Int = PadWorkspaceSchema.currentVersion,
        exportedAt: Date = Date(),
        appVersion: String = "1.0",
        activeWorkspaceId: String? = nil,
        workspaces: [Workspace]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.activeWorkspaceId = activeWorkspaceId
        self.workspaces = workspaces
    }
}
