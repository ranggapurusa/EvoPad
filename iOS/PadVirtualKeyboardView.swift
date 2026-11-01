import SwiftUI

/// Keyboard layout modes for EvoPad virtual keyboard
enum PadKeyboardLayoutMode: String, CaseIterable, Identifiable {
    case letters = "ABC"
    case numbers = "123"
    case navigation = "Nav / Fn"

    var id: String { rawValue }
}

/// Key item representation in the virtual keyboard grid
struct PadKeyItem: Identifiable {
    let id = UUID()
    let label: String
    let keyCode: UInt16
    let shiftLabel: String?
    let widthFlex: CGFloat
    let isSpecial: Bool

    init(label: String, keyCode: UInt16, shiftLabel: String? = nil, widthFlex: CGFloat = 1.0, isSpecial: Bool = false) {
        self.label = label
        self.keyCode = keyCode
        self.shiftLabel = shiftLabel
        self.widthFlex = widthFlex
        self.isSpecial = isSpecial
    }
}

struct PadVirtualKeyboardView: View {
    @ObservedObject var connection: PadConnectionManager

    // Persistent modifier states synced with parent
    @Binding var isCmdActive: Bool
    @Binding var isOptActive: Bool
    @Binding var isCtrlActive: Bool
    @Binding var isShiftActive: Bool

    @State private var layoutMode: PadKeyboardLayoutMode = .letters
    @State private var isCapsLockActive = false

    private var activeModifiers: [PadModifierFlagV2] {
        var mods: [PadModifierFlagV2] = []
        if isCmdActive { mods.append(.cmd) }
        if isOptActive { mods.append(.alt) }
        if isCtrlActive { mods.append(.ctrl) }
        if isShiftActive || isCapsLockActive { mods.append(.shift) }
        return mods
    }

    var body: some View {
        VStack(spacing: 8) {
            // Mode selector and modifier bar
            HStack(spacing: 8) {
                // Layout mode switch
                Picker("Layout", selection: $layoutMode) {
                    ForEach(PadKeyboardLayoutMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Spacer()

                // Modifiers
                modifierKey(title: "⌘ Cmd", isActive: $isCmdActive)
                modifierKey(title: "⌥ Opt", isActive: $isOptActive)
                modifierKey(title: "⌃ Ctrl", isActive: $isCtrlActive)
                modifierKey(title: "⇧ Shift", isActive: $isShiftActive)
            }
            .padding(.horizontal, 4)

            // Dynamic Keyboard Layout
            switch layoutMode {
            case .letters:
                lettersLayout
            case .numbers:
                numbersSymbolsLayout
            case .navigation:
                navigationFunctionLayout
            }
        }
        .padding(10)
        .background(Color(red: 0.12, green: 0.13, blue: 0.16).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Layout 1: Letters (QWERTY)

    private var lettersLayout: some View {
        VStack(spacing: 6) {
            // Row 1: Q W E R T Y U I O P
            HStack(spacing: 5) {
                keyButton("Q", key: .q, shift: "Q")
                keyButton("W", key: .w, shift: "W")
                keyButton("E", key: .e, shift: "E")
                keyButton("R", key: .r, shift: "R")
                keyButton("T", key: .t, shift: "T")
                keyButton("Y", key: .y, shift: "Y")
                keyButton("U", key: .u, shift: "U")
                keyButton("I", key: .i, shift: "I")
                keyButton("O", key: .o, shift: "O")
                keyButton("P", key: .p, shift: "P")
                keyButton("⌫", key: .delete, widthFlex: 1.3, isSpecial: true)
            }

            // Row 2: A S D F G H J K L Return
            HStack(spacing: 5) {
                keyButton("Tab", key: .tab, widthFlex: 1.2, isSpecial: true)
                keyButton("A", key: .a, shift: "A")
                keyButton("S", key: .s, shift: "S")
                keyButton("D", key: .d, shift: "D")
                keyButton("F", key: .f, shift: "F")
                keyButton("G", key: .g, shift: "G")
                keyButton("H", key: .h, shift: "H")
                keyButton("J", key: .j, shift: "J")
                keyButton("K", key: .k, shift: "K")
                keyButton("L", key: .l, shift: "L")
                keyButton("⏎", key: .returnKey, widthFlex: 1.4, isSpecial: true)
            }

            // Row 3: Shift Z X C V B N M , . Shift
            HStack(spacing: 5) {
                capsLockButton
                keyButton("Z", key: .z, shift: "Z")
                keyButton("X", key: .x, shift: "X")
                keyButton("C", key: .c, shift: "C")
                keyButton("V", key: .v, shift: "V")
                keyButton("B", key: .b, shift: "B")
                keyButton("N", key: .n, shift: "N")
                keyButton("M", key: .m, shift: "M")
                keyButton(",", key: .comma, shift: "<")
                keyButton(".", key: .period, shift: ">")
                keyButton("Esc", key: .escape, widthFlex: 1.2, isSpecial: true)
            }

            // Row 4: Spacebar & Arrows
            HStack(spacing: 5) {
                keyButton("Space", key: .space, widthFlex: 4.5, isSpecial: true)
                keyButton("←", key: .leftArrow, isSpecial: true)
                keyButton("↑", key: .upArrow, isSpecial: true)
                keyButton("↓", key: .downArrow, isSpecial: true)
                keyButton("→", key: .rightArrow, isSpecial: true)
            }
        }
    }

    // MARK: - Layout 2: Numbers & Symbols

    private var numbersSymbolsLayout: some View {
        VStack(spacing: 6) {
            // Row 1: Numbers 1 2 3 4 5 6 7 8 9 0 - = Delete
            HStack(spacing: 5) {
                keyButton("1", key: .one, shift: "!")
                keyButton("2", key: .two, shift: "@")
                keyButton("3", key: .three, shift: "#")
                keyButton("4", key: .four, shift: "$")
                keyButton("5", key: .five, shift: "%")
                keyButton("6", key: .six, shift: "^")
                keyButton("7", key: .seven, shift: "&")
                keyButton("8", key: .eight, shift: "*")
                keyButton("9", key: .nine, shift: "(")
                keyButton("0", key: .zero, shift: ")")
                keyButton("-", key: .minus, shift: "_")
                keyButton("=", key: .equal, shift: "+")
                keyButton("⌫", key: .delete, widthFlex: 1.2, isSpecial: true)
            }

            // Row 2: Symbols [ ] \ ; ' `
            HStack(spacing: 5) {
                keyButton("`", key: .grave, shift: "~")
                keyButton("[", key: .leftBracket, shift: "{")
                keyButton("]", key: .rightBracket, shift: "}")
                keyButton("\\", key: .backslash, shift: "|")
                keyButton(";", key: .semicolon, shift: ":")
                keyButton("'", key: .quote, shift: "\"")
                keyButton("/", key: .slash, shift: "?")
                keyButton("⏎", key: .returnKey, widthFlex: 1.5, isSpecial: true)
            }

            // Row 3: Spacebar & Quick Numbers
            HStack(spacing: 5) {
                keyButton("Tab", key: .tab, widthFlex: 1.2, isSpecial: true)
                keyButton("Space", key: .space, widthFlex: 4.0, isSpecial: true)
                keyButton("Esc", key: .escape, widthFlex: 1.2, isSpecial: true)
                keyButton("←", key: .leftArrow, isSpecial: true)
                keyButton("↑", key: .upArrow, isSpecial: true)
                keyButton("↓", key: .downArrow, isSpecial: true)
                keyButton("→", key: .rightArrow, isSpecial: true)
            }
        }
    }

    // MARK: - Layout 3: Navigation & Function Keys

    private var navigationFunctionLayout: some View {
        VStack(spacing: 6) {
            // Function Keys Row 1: F1 - F6
            HStack(spacing: 5) {
                keyButton("F1", key: .f1, isSpecial: true)
                keyButton("F2", key: .f2, isSpecial: true)
                keyButton("F3", key: .f3, isSpecial: true)
                keyButton("F4", key: .f4, isSpecial: true)
                keyButton("F5", key: .f5, isSpecial: true)
                keyButton("F6", key: .f6, isSpecial: true)
            }

            // Function Keys Row 2: F7 - F12
            HStack(spacing: 5) {
                keyButton("F7", key: .f7, isSpecial: true)
                keyButton("F8", key: .f8, isSpecial: true)
                keyButton("F9", key: .f9, isSpecial: true)
                keyButton("F10", key: .f10, isSpecial: true)
                keyButton("F11", key: .f11, isSpecial: true)
                keyButton("F12", key: .f12, isSpecial: true)
            }

            // Navigation Row: Home, End, PageUp, PageDown, ForwardDelete
            HStack(spacing: 5) {
                keyButton("Home", key: .home, isSpecial: true)
                keyButton("End", key: .end, isSpecial: true)
                keyButton("PgUp", key: .pageUp, isSpecial: true)
                keyButton("PgDn", key: .pageDown, isSpecial: true)
                keyButton("⌦ Del", key: .forwardDelete, isSpecial: true)
                keyButton("Esc", key: .escape, isSpecial: true)
            }

            // Arrow cluster
            HStack(spacing: 5) {
                Spacer()
                keyButton("←", key: .leftArrow, widthFlex: 1.5, isSpecial: true)
                VStack(spacing: 4) {
                    keyButton("↑", key: .upArrow, widthFlex: 1.5, isSpecial: true)
                    keyButton("↓", key: .downArrow, widthFlex: 1.5, isSpecial: true)
                }
                keyButton("→", key: .rightArrow, widthFlex: 1.5, isSpecial: true)
                Spacer()
            }
        }
    }

    // MARK: - Components

    private func keyButton(
        _ label: String,
        key: PadVirtualKey,
        shift: String? = nil,
        widthFlex: CGFloat = 1.0,
        isSpecial: Bool = false
    ) -> some View {
        let displayLabel = (isShiftActive || isCapsLockActive) ? (shift ?? label.uppercased()) : label.lowercased()

        return Button {
            pressKey(keyCode: key.rawValue)
        } label: {
            Text(isSpecial ? label : displayLabel)
                .font(.system(size: isSpecial ? 12 : 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(isSpecial ? Color.white.opacity(0.12) : Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 26 * widthFlex)
        .disabled(!connection.isAuthenticated)
    }

    private var capsLockButton: some View {
        Button {
            isCapsLockActive.toggle()
        } label: {
            Text("⇪")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isCapsLockActive ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(isCapsLockActive ? Color.indigo : Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 32)
        .disabled(!connection.isAuthenticated)
    }

    private func modifierKey(title: String, isActive: Binding<Bool>) -> some View {
        Button {
            isActive.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isActive.wrappedValue ? Color.indigo : Color.white.opacity(0.08))
                .foregroundStyle(isActive.wrappedValue ? .white : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!connection.isAuthenticated)
    }

    private func pressKey(keyCode: UInt16) {
        let mods = activeModifiers
        connection.sendKeyEvent(keyCode: keyCode, phase: .press, modifiers: mods.isEmpty ? nil : mods)

        // Reset momentary Shift key after pressing a key (Caps lock stays on)
        if isShiftActive {
            isShiftActive = false
        }
    }
}
