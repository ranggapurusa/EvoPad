import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Keyboard layout modes for EvoPad virtual keyboard
enum PadKeyboardLayoutMode: String, CaseIterable, Identifiable {
    case letters = "ABC"
    case numbers = "123"
    case numpad = "Numpad"
    case navigation = "Fn / Nav"

    var id: String { rawValue }
}

struct PadVirtualKeyboardView: View {
    @ObservedObject var connection: PadConnectionManager

    // Persistent modifier states synced with parent
    @Binding var isCmdActive: Bool
    @Binding var isOptActive: Bool
    @Binding var isCtrlActive: Bool
    @Binding var isShiftActive: Bool
    @State var isFnActive: Bool = false

    @State var layoutMode: PadKeyboardLayoutMode = .letters
    @State private var isCapsLockActive = false

    var activeModifiers: [PadModifierFlagV2] {
        var mods: [PadModifierFlagV2] = []
        if isCmdActive { mods.append(.cmd) }
        if isOptActive { mods.append(.alt) }
        if isCtrlActive { mods.append(.ctrl) }
        if isShiftActive || isCapsLockActive { mods.append(.shift) }
        if isFnActive { mods.append(.fn) }
        return mods
    }

    var body: some View {
        VStack(spacing: 8) {
            // Mode selector & Modifier summary
            HStack(spacing: 8) {
                Picker("Layout", selection: $layoutMode) {
                    ForEach(PadKeyboardLayoutMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Spacer()

                if !activeModifiers.isEmpty {
                    Button("Lepas Modifier") {
                        isCmdActive = false
                        isOptActive = false
                        isCtrlActive = false
                        isShiftActive = false
                        isFnActive = false
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(EvoTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(EvoTheme.keySurface, in: Capsule())
                }
            }
            .frame(height: 32)
            .padding(.horizontal, 4)

            // Dynamic Layouts
            Group {
                switch layoutMode {
                case .letters:
                    lettersLayout
                case .numbers:
                    numbersSymbolsLayout
                case .numpad:
                    numpadMathLayout
                case .navigation:
                    navigationFunctionLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EvoTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(EvoTheme.border, lineWidth: 1)
        )
        .accessibilityIdentifier("evopad.virtualKeyboard")
    }

    // MARK: - Layout 1: MacBook Pro Layout with Dedicated Function Row (Esc + F1-F12)

    private var lettersLayout: some View {
        VStack(spacing: 5) {
            // Row 1: Dedicated Function Row (Esc + F1-F12 + Del ⌦)
            HStack(spacing: 4) {
                keyButton("esc", key: .escape, widthFlex: 1.4, isSpecial: true)
                keyButton("F1", key: .f1, isSpecial: true)
                keyButton("F2", key: .f2, isSpecial: true)
                keyButton("F3", key: .f3, isSpecial: true)
                keyButton("F4", key: .f4, isSpecial: true)
                Spacer().frame(width: 6)
                keyButton("F5", key: .f5, isSpecial: true)
                keyButton("F6", key: .f6, isSpecial: true)
                keyButton("F7", key: .f7, isSpecial: true)
                keyButton("F8", key: .f8, isSpecial: true)
                Spacer().frame(width: 6)
                keyButton("F9", key: .f9, isSpecial: true)
                keyButton("F10", key: .f10, isSpecial: true)
                keyButton("F11", key: .f11, isSpecial: true)
                keyButton("F12", key: .f12, isSpecial: true)
                keyButton("del ⌦", key: .forwardDelete, widthFlex: 1.4, isSpecial: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Row 2: Number Row (`~ + 1-0 - = + Wide Delete)
            HStack(spacing: 4) {
                keyButton("`", key: .grave, shift: "~")
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
                keyButton("delete ⌫", key: .delete, widthFlex: 2.3, isSpecial: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Row 3: Top Letter Row (Tab ⇥ + QWERTY + [ ] \)
            HStack(spacing: 4) {
                keyButton("tab ⇥", key: .tab, widthFlex: 1.6, isSpecial: true)
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
                keyButton("[", key: .leftBracket, shift: "{")
                keyButton("]", key: .rightBracket, shift: "}")
                keyButton("\\", key: .backslash, shift: "|", widthFlex: 1.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Row 4: Home Letter Row (Caps Lock + ASDF + ; ' + Wide Return)
            HStack(spacing: 4) {
                capsLockButton(widthFlex: 2.0)
                keyButton("A", key: .a, shift: "A")
                keyButton("S", key: .s, shift: "S")
                keyButton("D", key: .d, shift: "D")
                keyButton("F", key: .f, shift: "F")
                keyButton("G", key: .g, shift: "G")
                keyButton("H", key: .h, shift: "H")
                keyButton("J", key: .j, shift: "J")
                keyButton("K", key: .k, shift: "K")
                keyButton("L", key: .l, shift: "L")
                keyButton(";", key: .semicolon, shift: ":")
                keyButton("'", key: .quote, shift: "\"")
                keyButton("return ⏎", key: .returnKey, widthFlex: 2.3, isSpecial: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Row 5: Shift Row (Left Shift + ZXCVB + , . / + Right Shift)
            HStack(spacing: 4) {
                shiftToggleButton(widthFlex: 2.4)
                keyButton("Z", key: .z, shift: "Z")
                keyButton("X", key: .x, shift: "X")
                keyButton("C", key: .c, shift: "C")
                keyButton("V", key: .v, shift: "V")
                keyButton("B", key: .b, shift: "B")
                keyButton("N", key: .n, shift: "N")
                keyButton("M", key: .m, shift: "M")
                keyButton(",", key: .comma, shift: "<")
                keyButton(".", key: .period, shift: ">")
                keyButton("/", key: .slash, shift: "?")
                shiftToggleButton(widthFlex: 2.9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Row 6: Bottom Row (Modifiers + Space + Navigation Arrows)
            HStack(spacing: 4) {
                modifierToggleButton("fn", sub: "🌐", isActive: $isFnActive, widthFlex: 0.8)
                modifierToggleButton("⌃", sub: "control", isActive: $isCtrlActive, widthFlex: 0.9)
                modifierToggleButton("⌥", sub: "option", isActive: $isOptActive, widthFlex: 0.9)
                modifierToggleButton("⌘", sub: "command", isActive: $isCmdActive, widthFlex: 1.1)
                keyButton("Space", key: .space, widthFlex: 6.0, isSpecial: false)
                modifierToggleButton("⌘", sub: "command", isActive: $isCmdActive, widthFlex: 1.1)
                modifierToggleButton("⌥", sub: "option", isActive: $isOptActive, widthFlex: 0.9)
                keyButton("←", key: .leftArrow, widthFlex: 1.0, isSpecial: true)
                keyButton("↑", key: .upArrow, widthFlex: 1.0, isSpecial: true)
                keyButton("↓", key: .downArrow, widthFlex: 1.0, isSpecial: true)
                keyButton("→", key: .rightArrow, widthFlex: 1.0, isSpecial: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout 2: Numbers & Symbols

    private var numbersSymbolsLayout: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                keyButton("`", key: .grave, shift: "~")
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
                keyButton("⌫", key: .delete, widthFlex: 1.3, isSpecial: true)
            }

            HStack(spacing: 5) {
                keyButton("Tab", key: .tab, widthFlex: 1.2, isSpecial: true)
                keyButton("!", key: .one, shift: "1")
                keyButton("@", key: .two, shift: "2")
                keyButton("#", key: .three, shift: "3")
                keyButton("$", key: .four, shift: "4")
                keyButton("%", key: .five, shift: "5")
                keyButton("^", key: .six, shift: "6")
                keyButton("&", key: .seven, shift: "7")
                keyButton("*", key: .eight, shift: "8")
                keyButton("(", key: .nine, shift: "9")
                keyButton(")", key: .zero, shift: "0")
                keyButton("⏎", key: .returnKey, widthFlex: 1.4, isSpecial: true)
            }

            HStack(spacing: 5) {
                keyButton("Esc", key: .escape, widthFlex: 1.2, isSpecial: true)
                keyButton("-", key: .minus, shift: "_")
                keyButton("=", key: .equal, shift: "+")
                keyButton("[", key: .leftBracket, shift: "{")
                keyButton("]", key: .rightBracket, shift: "}")
                keyButton("\\", key: .backslash, shift: "|")
                keyButton(";", key: .semicolon, shift: ":")
                keyButton("'", key: .quote, shift: "\"")
                keyButton(",", key: .comma, shift: "<")
                keyButton(".", key: .period, shift: ">")
                keyButton("/", key: .slash, shift: "?")
            }

            HStack(spacing: 4) {
                modifierToggleButton("⌘", isActive: $isCmdActive, widthFlex: 1.25)
                modifierToggleButton("⌥", isActive: $isOptActive, widthFlex: 1.15)
                keyButton("Space", key: .space, widthFlex: 5.8, isSpecial: false)
                modifierToggleButton("⌘", isActive: $isCmdActive, widthFlex: 1.25)
                keyButton("←", key: .leftArrow, widthFlex: 1.15, isSpecial: true)
                keyButton("↓", key: .downArrow, widthFlex: 1.15, isSpecial: true)
                keyButton("→", key: .rightArrow, widthFlex: 1.15, isSpecial: true)
            }
        }
    }

    // MARK: - Layout 3: Navigation & Function Keys

    private var navigationFunctionLayout: some View {
        VStack(spacing: 6) {
            // F1 - F6
            HStack(spacing: 5) {
                keyButton("F1", key: .f1, isSpecial: true)
                keyButton("F2", key: .f2, isSpecial: true)
                keyButton("F3", key: .f3, isSpecial: true)
                keyButton("F4", key: .f4, isSpecial: true)
                keyButton("F5", key: .f5, isSpecial: true)
                keyButton("F6", key: .f6, isSpecial: true)
            }

            // F7 - F12
            HStack(spacing: 5) {
                keyButton("F7", key: .f7, isSpecial: true)
                keyButton("F8", key: .f8, isSpecial: true)
                keyButton("F9", key: .f9, isSpecial: true)
                keyButton("F10", key: .f10, isSpecial: true)
                keyButton("F11", key: .f11, isSpecial: true)
                keyButton("F12", key: .f12, isSpecial: true)
            }

            // Navigation: Home, End, PgUp, PgDn, Esc, Del
            HStack(spacing: 5) {
                keyButton("Esc", key: .escape, widthFlex: 1.1, isSpecial: true)
                keyButton("Home", key: .home, widthFlex: 1.2, isSpecial: true)
                keyButton("End", key: .end, widthFlex: 1.2, isSpecial: true)
                keyButton("PgUp", key: .pageUp, widthFlex: 1.2, isSpecial: true)
                keyButton("PgDn", key: .pageDown, widthFlex: 1.2, isSpecial: true)
                keyButton("Del ⌦", key: .forwardDelete, widthFlex: 1.3, isSpecial: true)
            }

            // Arrow cluster + modifiers
            HStack(spacing: 4) {
                modifierToggleButton("⌘", isActive: $isCmdActive, widthFlex: 1.25)
                modifierToggleButton("⌥", isActive: $isOptActive, widthFlex: 1.15)
                modifierToggleButton("⌃", isActive: $isCtrlActive, widthFlex: 1.15)
                modifierToggleButton("⇧", isActive: $isShiftActive, widthFlex: 1.25)
                keyButton("Space", key: .space, widthFlex: 5.5, isSpecial: false)
                keyButton("←", key: .leftArrow, widthFlex: 1.15, isSpecial: true)
                keyButton("↑", key: .upArrow, widthFlex: 1.15, isSpecial: true)
                keyButton("↓", key: .downArrow, widthFlex: 1.15, isSpecial: true)
                keyButton("→", key: .rightArrow, widthFlex: 1.15, isSpecial: true)
            }
        }
    }

    // MARK: - Layout 4: Numpad & Math Functions

    private var numpadMathLayout: some View {
        HStack(spacing: 12) {
            // Left Panel: Compact Math Functions (Secondary)
            VStack(spacing: 4) {
                // Header Label
                HStack {
                    Text("FUNGSI MATEMATIKA")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(EvoTheme.textTertiary)
                        .tracking(0.8)
                    Spacer()
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)

                // Row 1: Trigonometric & Constants
                HStack(spacing: 4) {
                    mathTextButton("sin", text: "sin(")
                    mathTextButton("cos", text: "cos(")
                    mathTextButton("tan", text: "tan(")
                    mathTextButton("π", text: "π")
                    mathTextButton("e", text: "e")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Row 2: Inverse Trig & Logarithms
                HStack(spacing: 4) {
                    mathTextButton("asin", text: "asin(")
                    mathTextButton("acos", text: "acos(")
                    mathTextButton("atan", text: "atan(")
                    mathTextButton("ln", text: "ln(")
                    mathTextButton("log", text: "log(")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Row 3: Powers & Roots
                HStack(spacing: 4) {
                    mathTextButton("x²", text: "^2")
                    mathTextButton("x³", text: "^3")
                    mathTextButton("xʸ", text: "^")
                    mathTextButton("√", text: "sqrt(")
                    mathTextButton("∛", text: "cbrt(")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Row 4: Fractions, Abs, Factorial & Parentheses
                HStack(spacing: 4) {
                    mathTextButton("1/x", text: "^(-1)")
                    mathTextButton("|x|", text: "abs(")
                    mathKeyButton("!", key: .one, withShift: true)
                    mathKeyButton("(", key: .nine, withShift: true)
                    mathKeyButton(")", key: .zero, withShift: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Row 5: Mod, Exponent, Percent, Constants
                HStack(spacing: 4) {
                    mathTextButton("mod", text: "%")
                    mathKeyButton("^", key: .six, withShift: true)
                    mathKeyButton("%", key: .five, withShift: true)
                    mathTextButton("Ans", text: "Ans")
                    mathTextButton("rad", text: "rad")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 240)
            .frame(maxHeight: .infinity)

            // Divider
            Rectangle()
                .fill(EvoTheme.border)
                .frame(width: 1)
                .padding(.vertical, 6)

            // Right Panel: Large Dominant Numpad (Primary)
            VStack(spacing: 6) {
                // Row 1: Clear, Negate, Divide, Delete
                HStack(spacing: 6) {
                    numpadButton("C", key: .escape, isAction: true)
                    numpadTextButton("±", text: "-", isAction: true)
                    numpadButton("÷", key: .keypadDivide, isAction: true)
                    numpadButton("⌫", key: .delete, isAction: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Row 2: 7, 8, 9, Multiply
                HStack(spacing: 6) {
                    numpadButton("7", key: .keypad7)
                    numpadButton("8", key: .keypad8)
                    numpadButton("9", key: .keypad9)
                    numpadButton("×", key: .keypadMultiply, isAction: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Row 3: 4, 5, 6, Subtract
                HStack(spacing: 6) {
                    numpadButton("4", key: .keypad4)
                    numpadButton("5", key: .keypad5)
                    numpadButton("6", key: .keypad6)
                    numpadButton("−", key: .keypadMinus, isAction: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Row 4: 1, 2, 3, Plus
                HStack(spacing: 6) {
                    numpadButton("1", key: .keypad1)
                    numpadButton("2", key: .keypad2)
                    numpadButton("3", key: .keypad3)
                    numpadButton("+", key: .keypadPlus, isAction: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Row 5: 0, Decimal, Equals, Enter
                HStack(spacing: 6) {
                    numpadButton("0", key: .keypad0, widthFlex: 1.2)
                    numpadButton(".", key: .keypadDecimal)
                    numpadButton("=", key: .keypadEquals, isAction: true)
                    numpadButton("⏎", key: .keypadEnter, isProminent: true, widthFlex: 1.3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Key Buttons & Modifiers

    private func numpadButton(
        _ label: String,
        key: PadVirtualKey,
        isAction: Bool = false,
        isProminent: Bool = false,
        widthFlex: CGFloat = 1.0
    ) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: isProminent ? .medium : .light).impactOccurred()
            #endif
            pressKey(keyCode: key.rawValue)
        } label: {
            Text(label)
                .font(.system(size: isAction ? 20 : 24, weight: isAction ? .bold : .semibold, design: .rounded))
                .foregroundStyle(isProminent ? Color.white : (isAction ? EvoTheme.accent : EvoTheme.textPrimary))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    isProminent ? EvoTheme.accent : (isAction ? EvoTheme.panel : EvoTheme.keySurface),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isProminent ? EvoTheme.borderStrong : EvoTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(EvoKeyButtonStyle())
        .frame(minWidth: 32 * widthFlex, maxWidth: .infinity)
        .disabled(!connection.isAuthenticated)
    }

    private func numpadTextButton(
        _ label: String,
        text: String,
        isAction: Bool = true,
        widthFlex: CGFloat = 1.0
    ) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            connection.sendTextInput(text)
        } label: {
            Text(label)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(isAction ? EvoTheme.accent : EvoTheme.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(EvoTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(EvoKeyButtonStyle())
        .frame(minWidth: 32 * widthFlex, maxWidth: .infinity)
        .disabled(!connection.isAuthenticated)
    }

    private func mathTextButton(_ label: String, text: String, widthFlex: CGFloat = 1.0) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            connection.sendTextInput(text)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(EvoTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(EvoTheme.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(EvoTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(EvoKeyButtonStyle())
        .frame(minWidth: 16 * widthFlex, maxWidth: .infinity)
        .disabled(!connection.isAuthenticated)
    }

    private func mathKeyButton(_ label: String, key: PadVirtualKey, withShift: Bool = false) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            var mods = activeModifiers
            if withShift && !mods.contains(.shift) {
                mods.append(.shift)
            }
            connection.sendKeyEvent(keyCode: key.rawValue, phase: .press, modifiers: mods.isEmpty ? nil : mods)
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(EvoTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(EvoTheme.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(EvoTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(EvoKeyButtonStyle())
        .frame(minWidth: 16, maxWidth: .infinity)
        .disabled(!connection.isAuthenticated)
    }

    private func keyButton(
        _ label: String,
        key: PadVirtualKey,
        shift: String? = nil,
        widthFlex: CGFloat = 1.0,
        minHeight: CGFloat = 32,
        isSpecial: Bool = false,
        isProminent: Bool = false
    ) -> some View {
        let isShifted = isShiftActive || isCapsLockActive
        let displayLabel = isShifted ? (shift ?? label.uppercased()) : label.lowercased()

        return Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            pressKey(keyCode: key.rawValue)
        } label: {
            Text(isSpecial ? label : displayLabel)
                .font(.system(size: isSpecial ? (minHeight < 24 ? 11 : 12) : 14, weight: isProminent ? .bold : .medium, design: isSpecial ? .default : .rounded))
                .foregroundStyle(isProminent ? Color.white : EvoTheme.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isProminent ? EvoTheme.accent : (isSpecial ? EvoTheme.panel : EvoTheme.keySurface), in: RoundedRectangle(cornerRadius: minHeight < 24 ? 5 : 8))
                .overlay(
                    RoundedRectangle(cornerRadius: minHeight < 24 ? 5 : 8)
                        .strokeBorder(isProminent ? EvoTheme.borderStrong : EvoTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(EvoKeyButtonStyle())
        .frame(minWidth: 20 * widthFlex, maxWidth: .infinity)
        .disabled(!connection.isAuthenticated)
    }

    private func shiftToggleButton(widthFlex: CGFloat = 1.0) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            isShiftActive.toggle()
        } label: {
            HStack(spacing: 4) {
                Text("⇧")
                    .font(.system(size: 13, weight: .bold))
                Text("shift")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isShiftActive ? Color.white : EvoTheme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isShiftActive ? EvoTheme.accent : EvoTheme.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isShiftActive ? EvoTheme.borderStrong : EvoTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(EvoKeyButtonStyle())
        .frame(minWidth: 22 * widthFlex, maxWidth: .infinity)
        .disabled(!connection.isAuthenticated)
    }

    private func capsLockButton(widthFlex: CGFloat = 1.0) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            isCapsLockActive.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isCapsLockActive ? Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255) : Color.white.opacity(0.18))
                    .frame(width: 5, height: 5)
                Text("caps lock")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isCapsLockActive ? Color.white : EvoTheme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isCapsLockActive ? EvoTheme.accent : EvoTheme.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isCapsLockActive ? EvoTheme.borderStrong : EvoTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(EvoKeyButtonStyle())
        .frame(minWidth: 22 * widthFlex, maxWidth: .infinity)
        .disabled(!connection.isAuthenticated)
    }

    private func modifierToggleButton(
        _ label: String,
        sub: String? = nil,
        isActive: Binding<Bool>,
        widthFlex: CGFloat = 1.0
    ) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            isActive.wrappedValue.toggle()
        } label: {
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                if let sub {
                    Text(sub)
                        .font(.system(size: 8, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .opacity(0.85)
                }
            }
            .foregroundStyle(isActive.wrappedValue ? Color.white : EvoTheme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isActive.wrappedValue ? EvoTheme.accent : EvoTheme.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isActive.wrappedValue ? EvoTheme.borderStrong : EvoTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(EvoKeyButtonStyle())
        .frame(minWidth: 16 * widthFlex, maxWidth: .infinity)
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

struct EvoKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
