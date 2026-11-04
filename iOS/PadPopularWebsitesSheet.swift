import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Tampilan Katalog Shortcut Situs Populer (YouTube, Google, GitHub, ChatGPT/Claude, Twitter/X, Netflix, Spotify, Reddit)
/// Ditaruh langsung sebagai Tab di sebelah Workspace tanpa modal popup.
struct PadPopularWebsitesView: View {
    @ObservedObject var connection: PadConnectionManager
    @ObservedObject var macroStore: PadMacroStore = .shared

    @State private var selectedSiteId: String = "site.youtube"
    @State private var feedbackMessage: String?
    @State private var searchText: String = ""

    private var sites: [PopularWebSite] {
        PopularWebsitesCatalog.sites
    }

    private var selectedSite: PopularWebSite {
        sites.first(where: { $0.id == selectedSiteId }) ?? sites[0]
    }

    private var filteredShortcuts: [WebShortcutItem] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return selectedSite.shortcuts
        }
        let query = searchText.lowercased()
        return selectedSite.shortcuts.filter {
            $0.title.lowercased().contains(query) ||
            $0.hotkeyDisplay.lowercased().contains(query) ||
            $0.description.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // MARK: - 1. Horizontal Website Category Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sites) { site in
                        let isSelected = (site.id == selectedSite.id)
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedSiteId = site.id
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: site.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.white : site.themeColor)

                                Text(site.name)
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? Color.white : EvoTheme.textPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? site.themeColor : EvoTheme.panel,
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

            // MARK: - 2. Current Site Info & Direct Open in Chrome/Browser Button
            HStack(spacing: 12) {
                Image(systemName: selectedSite.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(selectedSite.themeColor)
                    .frame(width: 38, height: 38)
                    .background(EvoTheme.keySurface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(selectedSite.themeColor.opacity(0.35), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(selectedSite.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(EvoTheme.textPrimary)

                        Text("•")
                            .foregroundStyle(EvoTheme.textTertiary)

                        Text(selectedSite.url.replacingOccurrences(of: "https://", with: ""))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(EvoTheme.textSecondary)
                    }

                    Text(selectedSite.description)
                        .font(.system(size: 11))
                        .foregroundStyle(EvoTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Direct Open in Mac (Opens Google Chrome / Default Browser)
                Button {
                    openSiteOnMac(selectedSite)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Buka di Mac")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(selectedSite.themeColor, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!connection.isAuthenticated)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(EvoTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(EvoTheme.border, lineWidth: 1)
            )

            // MARK: - 3. Quick Search Filter
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(EvoTheme.textTertiary)

                TextField("Cari shortcut \(selectedSite.name)...", text: $searchText)
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

            // MARK: - 4. Shortcuts Grid / List
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                    ForEach(filteredShortcuts) { item in
                        Button {
                            triggerShortcut(item)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(selectedSite.themeColor)
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

            // MARK: - Feedback Banner
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

    private func triggerShortcut(_ item: WebShortcutItem) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        if let macroId = item.macroId, let found = macroStore.macros.first(where: { $0.id == macroId }) {
            connection.sendMacro(macroId: found.id, steps: found.steps)
            showFeedback("Macro: \(found.name)")
            return
        }

        if let keyCode = item.keyCode {
            connection.sendCustomShortcut(keyCode: keyCode, modifiers: item.modifiers)
            showFeedback("Shortcut: \(item.title) (\(item.hotkeyDisplay))")
        }
    }

    private func openSiteOnMac(_ site: PopularWebSite) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        // Direct launchApp action with URL target: MacServer launches Google Chrome or default browser directly
        let openSteps = [
            PadMacroStepV2(action: "launchApp", keyCode: nil, modifiers: nil, text: site.url, delayMs: nil)
        ]
        connection.sendMacro(macroId: "launch.\(site.id)", steps: openSteps)
        showFeedback("Membuka \(site.name) di Mac...")
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

/// Compatibility wrapper for existing sheet references
struct PadPopularWebsitesSheet: View {
    @ObservedObject var connection: PadConnectionManager

    var body: some View {
        PadPopularWebsitesView(connection: connection)
    }
}
