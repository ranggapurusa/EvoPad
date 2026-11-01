import SwiftUI

/// M4.4 Custom Control Panel for iPad: One-handed thumb-friendly grid
/// for Media Control, System Actions, and favorite macros.
struct PadControlPanelView: View {
    @ObservedObject var connection: PadConnectionManager
    @ObservedObject var macroStore = PadMacroStore.shared

    var body: some View {
        VStack(spacing: 12) {
            // Media Control Section
            VStack(alignment: .leading, spacing: 6) {
                Label("MEDIA CONTROLLER", systemImage: "play.rectangle.fill")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 4)

                HStack(spacing: 8) {
                    mediaButton(key: .previousTrack)
                    mediaButton(key: .playPause, highlight: true)
                    mediaButton(key: .nextTrack)
                    Divider().frame(height: 28).background(Color.white.opacity(0.15))
                    mediaButton(key: .volumeDown)
                    mediaButton(key: .volumeUp)
                    mediaButton(key: .mute)
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

            // System Control Section
            VStack(alignment: .leading, spacing: 6) {
                Label("SYSTEM CONTROL", systemImage: "macwindow")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 4)

                HStack(spacing: 8) {
                    systemButton(action: .lockScreen)
                    systemButton(action: .sleep)
                    systemButton(action: .screenshot)
                    systemButton(action: .launchApp, targetApp: "com.apple.Terminal", label: "Terminal")
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 4)
    }

    private func mediaButton(key: PadMediaControlKey, highlight: Bool = false) -> some View {
        Button {
            connection.sendMediaKey(key)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: key.symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(key.title)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(highlight ? Color.indigo : Color.white.opacity(0.08))
            .foregroundStyle(highlight ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!connection.isAuthenticated)
    }

    private func systemButton(action: PadSystemControlAction, targetApp: String? = nil, label: String? = nil) -> some View {
        Button {
            connection.sendSystemAction(action, targetApp: targetApp)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: action.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(action == .lockScreen || action == .sleep ? .orange : .indigo)
                Text(label ?? action.title)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!connection.isAuthenticated)
    }
}
