import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Virtual Touch Bar strip displayed directly above the virtual keyboard.
/// Strictly binds only to existing keyboard, shortcut, media, and system actions in EvoPad.
struct EvoTouchBarView: View {
    @ObservedObject var connection: PadConnectionManager
    let activeModifiers: [PadModifierFlagV2]
    let onTriggerShortcut: (PadStandardShortcut) -> Void
    var onOpenWebShortcuts: (() -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // 1. Escape Key
                touchBarButton(
                    title: "esc",
                    symbol: nil,
                    isProminent: true
                ) {
                    connection.sendKeyEvent(
                        keyCode: PadVirtualKey.escape.rawValue,
                        phase: .press,
                        modifiers: activeModifiers
                    )
                }

                if let onOpenWeb = onOpenWebShortcuts {
                    groupDivider

                    touchBarButton(title: "Web", symbol: "globe") {
                        onOpenWeb()
                    }
                }

                groupDivider

                // 2. Application Shortcuts (Existing PadStandardShortcut)
                HStack(spacing: 6) {
                    touchBarShortcutButton(.undo, label: "Undo")
                    touchBarShortcutButton(.redo, label: "Redo")
                    touchBarShortcutButton(.cut, label: "Cut")
                    touchBarShortcutButton(.copy, label: "Copy")
                    touchBarShortcutButton(.paste, label: "Paste")
                    touchBarShortcutButton(.selectAll, label: "All")
                }

                groupDivider

                // 3. System & Workspace Navigation (Existing PadStandardShortcut + Screenshot)
                HStack(spacing: 6) {
                    touchBarShortcutButton(.spotlight, label: "Search")
                    touchBarShortcutButton(.missionControl, label: "Exposé")
                    touchBarShortcutButton(.commandTab, label: "Switch")
                    touchBarButton(title: "Capture", symbol: "camera.viewfinder") {
                        connection.sendSystemAction(.screenshot)
                    }
                }

                groupDivider

                // 4. Media Controls (Existing PadMediaControlKey)
                HStack(spacing: 6) {
                    touchBarMediaButton(.previousTrack, label: nil)
                    touchBarMediaButton(.playPause, label: nil)
                    touchBarMediaButton(.nextTrack, label: nil)
                }

                groupDivider

                // 5. Volume & System Controls (Existing PadMediaControlKey + Lock Screen)
                HStack(spacing: 6) {
                    touchBarMediaButton(.mute, label: nil)
                    touchBarMediaButton(.volumeDown, label: nil)
                    touchBarMediaButton(.volumeUp, label: nil)
                    touchBarButton(title: "Lock", symbol: "lock.fill") {
                        connection.sendSystemAction(.lockScreen)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(height: 42)
        .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(EvoTheme.border, lineWidth: 1)
        )
        .disabled(!connection.isAuthenticated)
        .opacity(connection.isAuthenticated ? 1.0 : 0.55)
        .accessibilityIdentifier("evopad.touchBar")
    }

    private var groupDivider: some View {
        Rectangle()
            .fill(EvoTheme.borderStrong)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
    }

    private func touchBarShortcutButton(_ shortcut: PadStandardShortcut, label: String) -> some View {
        touchBarButton(title: label, symbol: shortcut.symbol) {
            onTriggerShortcut(shortcut)
        }
    }

    private func touchBarMediaButton(_ key: PadMediaControlKey, label: String?) -> some View {
        touchBarButton(title: label, symbol: key.symbol) {
            connection.sendMediaKey(key)
        }
    }

    private func touchBarButton(
        title: String?,
        symbol: String?,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                if let title {
                    Text(title)
                        .font(.system(size: 11, weight: isProminent ? .semibold : .medium, design: isProminent ? .monospaced : .default))
                }
            }
            .foregroundStyle(EvoTheme.textPrimary)
            .padding(.horizontal, isProminent ? 14 : 10)
            .frame(height: 30)
            .background(isProminent ? EvoTheme.surface : EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(EvoTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(EvoTouchBarButtonStyle())
    }
}

struct EvoTouchBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
