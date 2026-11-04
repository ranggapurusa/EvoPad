import Foundation

/// Definition of a user-configurable or preset macro on iPad.
struct PadMacroDefinition: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var description: String
    var icon: String
    var steps: [PadMacroStepV2]

    init(id: String = UUID().uuidString, name: String, description: String, icon: String, steps: [PadMacroStepV2]) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.steps = steps
    }
}

/// Persistent store and catalog of macros on iPad.
final class PadMacroStore: ObservableObject {
    static let shared = PadMacroStore()

    @Published var macros: [PadMacroDefinition] = []

    private let storageKey = "id.evonex.evopad.macros.v1"

    init() {
        loadMacros()
    }

    func loadMacros() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([PadMacroDefinition].self, from: data),
           !saved.isEmpty {
            self.macros = saved
        } else {
            // Populate defaults
            self.macros = Self.presetMacros
            saveMacros()
        }
    }

    func saveMacros() {
        if let data = try? JSONEncoder().encode(macros) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func addOrUpdateMacro(_ macro: PadMacroDefinition) {
        if let index = macros.firstIndex(where: { $0.id == macro.id }) {
            macros[index] = macro
        } else {
            macros.append(macro)
        }
        saveMacros()
    }

    func deleteMacro(id: String) {
        macros.removeAll { $0.id == id }
        saveMacros()
    }

    func resetToDefaults() {
        macros = Self.presetMacros
        saveMacros()
    }

    // MARK: - Built-in Preset Macros

    static var presetMacros: [PadMacroDefinition] {
        [
            // Preset 1: Copy All (Cmd+A -> 50ms delay -> Cmd+C)
            PadMacroDefinition(
                id: "preset.copyAll",
                name: "Salin Semua",
                description: "Pilih seluruh teks lalu salin ke clipboard",
                icon: "doc.on.doc.fill",
                steps: [
                    PadMacroStepV2(action: "shortcut", keyCode: 0, modifiers: [.cmd], text: nil, delayMs: nil), // Cmd+A
                    PadMacroStepV2(action: "delay", keyCode: nil, modifiers: nil, text: nil, delayMs: 60),
                    PadMacroStepV2(action: "shortcut", keyCode: 8, modifiers: [.cmd], text: nil, delayMs: nil)  // Cmd+C
                ]
            ),

            // Preset 2: Duplicate Line (Cmd+C -> Down -> Cmd+V)
            PadMacroDefinition(
                id: "preset.duplicateLine",
                name: "Duplikat Baris",
                description: "Salin baris dan tempel di bawahnya",
                icon: "arrow.uturn.down.square.fill",
                steps: [
                    PadMacroStepV2(action: "shortcut", keyCode: 8, modifiers: [.cmd], text: nil, delayMs: nil), // Cmd+C
                    PadMacroStepV2(action: "delay", keyCode: nil, modifiers: nil, text: nil, delayMs: 50),
                    PadMacroStepV2(action: "key", keyCode: 125, modifiers: nil, text: nil, delayMs: nil),       // Down Arrow
                    PadMacroStepV2(action: "delay", keyCode: nil, modifiers: nil, text: nil, delayMs: 50),
                    PadMacroStepV2(action: "shortcut", keyCode: 9, modifiers: [.cmd], text: nil, delayMs: nil)  // Cmd+V
                ]
            ),

            // Preset 3: Browser New Tab & Open (Cmd+T -> delay -> Type URL)
            PadMacroDefinition(
                id: "preset.newTab",
                name: "Tab Baru Browser",
                description: "Buka tab browser baru",
                icon: "plus.square.fill",
                steps: [
                    PadMacroStepV2(action: "shortcut", keyCode: 17, modifiers: [.cmd], text: nil, delayMs: nil) // Cmd+T
                ]
            ),

            // Preset 4: Launch Terminal
            PadMacroDefinition(
                id: "preset.launchTerminal",
                name: "Buka Terminal",
                description: "Luncurkan aplikasi Terminal macOS",
                icon: "terminal.fill",
                steps: [
                    PadMacroStepV2(action: "launchApp", keyCode: nil, modifiers: nil, text: "com.apple.Terminal", delayMs: nil)
                ]
            ),

            // Preset 5: Open YouTube
            PadMacroDefinition(
                id: "preset.openYouTube",
                name: "Buka YouTube",
                description: "Buka YouTube langsung di Google Chrome / Browser Mac",
                icon: "play.rectangle.fill",
                steps: [
                    PadMacroStepV2(action: "launchApp", keyCode: nil, modifiers: nil, text: "https://youtube.com", delayMs: nil)
                ]
            ),

            // Preset 6: Open Google
            PadMacroDefinition(
                id: "preset.openGoogle",
                name: "Buka Google",
                description: "Buka Google Search di Browser Mac",
                icon: "magnifyingglass",
                steps: [
                    PadMacroStepV2(action: "launchApp", keyCode: nil, modifiers: nil, text: "https://google.com", delayMs: nil)
                ]
            ),

            // Preset 7: Open GitHub
            PadMacroDefinition(
                id: "preset.openGitHub",
                name: "Buka GitHub",
                description: "Buka GitHub di Browser Mac",
                icon: "chevron.left.forwardslash.chevron.right",
                steps: [
                    PadMacroStepV2(action: "launchApp", keyCode: nil, modifiers: nil, text: "https://github.com", delayMs: nil)
                ]
            ),

            // Preset 8: Open ChatGPT
            PadMacroDefinition(
                id: "preset.openChatGPT",
                name: "Buka ChatGPT",
                description: "Buka ChatGPT di Browser Mac",
                icon: "sparkles",
                steps: [
                    PadMacroStepV2(action: "launchApp", keyCode: nil, modifiers: nil, text: "https://chatgpt.com", delayMs: nil)
                ]
            ),

            // Preset 9: Open X (Twitter)
            PadMacroDefinition(
                id: "preset.openX",
                name: "Buka X / Twitter",
                description: "Buka x.com di Browser Mac",
                icon: "bubble.left.and.bubble.right.fill",
                steps: [
                    PadMacroStepV2(action: "launchApp", keyCode: nil, modifiers: nil, text: "https://x.com", delayMs: nil)
                ]
            ),

            // Preset 10: Open Netflix
            PadMacroDefinition(
                id: "preset.openNetflix",
                name: "Buka Netflix",
                description: "Buka Netflix di Browser Mac",
                icon: "film.fill",
                steps: [
                    PadMacroStepV2(action: "launchApp", keyCode: nil, modifiers: nil, text: "https://netflix.com", delayMs: nil)
                ]
            ),

            // Preset 11: Open Spotify Web
            PadMacroDefinition(
                id: "preset.openSpotify",
                name: "Buka Spotify Web",
                description: "Buka Spotify Web Player di Browser Mac",
                icon: "waveform",
                steps: [
                    PadMacroStepV2(action: "launchApp", keyCode: nil, modifiers: nil, text: "https://open.spotify.com", delayMs: nil)
                ]
            ),

            // Preset 12: Open Reddit
            PadMacroDefinition(
                id: "preset.openReddit",
                name: "Buka Reddit",
                description: "Buka Reddit di Browser Mac",
                icon: "flame.fill",
                steps: [
                    PadMacroStepV2(action: "launchApp", keyCode: nil, modifiers: nil, text: "https://reddit.com", delayMs: nil)
                ]
            )
        ]
    }
}
