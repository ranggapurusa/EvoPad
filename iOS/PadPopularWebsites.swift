import SwiftUI

// MARK: - Model Shortcut Situs Populer

struct WebShortcutItem: Identifiable {
    let id: String
    let title: String
    let hotkeyDisplay: String
    let icon: String
    let keyCode: UInt16?
    let modifiers: [PadModifierFlagV2]
    let macroId: String?
    let description: String

    init(
        id: String = UUID().uuidString,
        title: String,
        hotkeyDisplay: String,
        icon: String,
        keyCode: UInt16? = nil,
        modifiers: [PadModifierFlagV2] = [],
        macroId: String? = nil,
        description: String
    ) {
        self.id = id
        self.title = title
        self.hotkeyDisplay = hotkeyDisplay
        self.icon = icon
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.macroId = macroId
        self.description = description
    }
}

struct PopularWebSite: Identifiable {
    let id: String
    let name: String
    let url: String
    let icon: String
    let themeColor: Color
    let controlColor: ControlColor
    let description: String
    let openMacroId: String
    let shortcuts: [WebShortcutItem]
}

// MARK: - Katalog Situs Populer & Shortcuts

enum PopularWebsitesCatalog {
    static let sites: [PopularWebSite] = [
        // 1. YouTube
        PopularWebSite(
            id: "site.youtube",
            name: "YouTube",
            url: "https://youtube.com",
            icon: "play.rectangle.fill",
            themeColor: Color(red: 255 / 255, green: 0 / 255, blue: 0 / 255),
            controlColor: .red,
            description: "Platform streaming video & musik",
            openMacroId: "preset.openYouTube",
            shortcuts: [
                WebShortcutItem(title: "Play / Pause", hotkeyDisplay: "Space / K", icon: "playpause.fill", keyCode: 40, description: "Putar atau jeda video saat aktif"),
                WebShortcutItem(title: "Layar Penuh (Fullscreen)", hotkeyDisplay: "F", icon: "arrow.up.left.and.arrow.down.right", keyCode: 3, description: "Buka atau tutup tampilan layar penuh"),
                WebShortcutItem(title: "Mute / Unmute", hotkeyDisplay: "M", icon: "speaker.slash.fill", keyCode: 46, description: "Senyapkan audio seketika"),
                WebShortcutItem(title: "Mundur 10 Detik", hotkeyDisplay: "J", icon: "gobackward.10", keyCode: 38, description: "Putar mundur 10 detik"),
                WebShortcutItem(title: "Maju 10 Detik", hotkeyDisplay: "L", icon: "goforward.10", keyCode: 37, description: "Lompati 10 detik ke depan"),
                WebShortcutItem(title: "Subtitle (CC)", hotkeyDisplay: "C", icon: "captions.bubble.fill", keyCode: 8, description: "Aktifkan atau matikan takarir"),
                WebShortcutItem(title: "Video Berikutnya", hotkeyDisplay: "⇧ N", icon: "forward.end.fill", keyCode: 45, modifiers: [.shift], description: "Putar video berikutnya dalam playlist"),
                WebShortcutItem(title: "Buka YouTube", hotkeyDisplay: "⌘ T + URL", icon: "safari.fill", macroId: "preset.openYouTube", description: "Buka tab baru dan muat situs YouTube")
            ]
        ),

        // 2. Google & Browser
        PopularWebSite(
            id: "site.google",
            name: "Google & Browser",
            url: "https://google.com",
            icon: "magnifyingglass",
            themeColor: Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255),
            controlColor: .blue,
            description: "Mesin pencari & navigasi tab web browser",
            openMacroId: "preset.openGoogle",
            shortcuts: [
                WebShortcutItem(title: "Fokus Bar URL / Pencarian", hotkeyDisplay: "⌘ L", icon: "link", keyCode: 37, modifiers: [.cmd], description: "Sorot address bar untuk ketik URL baru"),
                WebShortcutItem(title: "Tab Baru", hotkeyDisplay: "⌘ T", icon: "plus.square.fill", keyCode: 17, modifiers: [.cmd], description: "Buka tab kosong baru"),
                WebShortcutItem(title: "Tutup Tab Aktif", hotkeyDisplay: "⌘ W", icon: "xmark.square.fill", keyCode: 13, modifiers: [.cmd], description: "Tutup tab browser yang sedang dibuka"),
                WebShortcutItem(title: "Buka Kembali Tab Terakhir", hotkeyDisplay: "⌘ ⇧ T", icon: "arrow.uturn.left.square.fill", keyCode: 17, modifiers: [.cmd, .shift], description: "Pulihkan tab yang baru saja ditutup"),
                WebShortcutItem(title: "Muat Ulang (Reload)", hotkeyDisplay: "⌘ R", icon: "arrow.clockwise", keyCode: 15, modifiers: [.cmd], description: "Refresh halaman web saat ini"),
                WebShortcutItem(title: "Cari di Halaman (Find)", hotkeyDisplay: "⌘ F", icon: "doc.text.magnifyingglass", keyCode: 3, modifiers: [.cmd], description: "Cari kata atau teks di halaman"),
                WebShortcutItem(title: "Halaman Sebelumnya", hotkeyDisplay: "⌘ [", icon: "chevron.left", keyCode: 33, modifiers: [.cmd], description: "Kembali ke halaman sebelumnya"),
                WebShortcutItem(title: "Buka Google", hotkeyDisplay: "⌘ T + URL", icon: "globe", macroId: "preset.openGoogle", description: "Buka tab baru ke Google Search")
            ]
        ),

        // 3. GitHub
        PopularWebSite(
            id: "site.github",
            name: "GitHub",
            url: "https://github.com",
            icon: "chevron.left.forwardslash.chevron.right",
            themeColor: Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255),
            controlColor: .purple,
            description: "Pusat kolaborasi & manajemen kode sumber",
            openMacroId: "preset.openGitHub",
            shortcuts: [
                WebShortcutItem(title: "File Finder", hotkeyDisplay: "T", icon: "folder.badge.gearshape", keyCode: 17, description: "Cari file proyek secara instan"),
                WebShortcutItem(title: "Pencarian Global Repo", hotkeyDisplay: "S / /", icon: "text.magnifyingglass", keyCode: 44, description: "Sorot input pencarian repository"),
                WebShortcutItem(title: "Ganti Branch / Tag", hotkeyDisplay: "W", icon: "arrow.triangle.branch", keyCode: 13, description: "Buka menu pemilihan branch"),
                WebShortcutItem(title: "Tampilkan Bantuan Shortcut", hotkeyDisplay: "⇧ / (?)", icon: "questionmark.circle.fill", keyCode: 44, modifiers: [.shift], description: "Buka daftar lengkap shortcut GitHub"),
                WebShortcutItem(title: "Buka GitHub", hotkeyDisplay: "⌘ T + URL", icon: "hammer.fill", macroId: "preset.openGitHub", description: "Buka tab baru dan akses GitHub")
            ]
        ),

        // 4. ChatGPT & Claude AI
        PopularWebSite(
            id: "site.ai",
            name: "ChatGPT & Claude",
            url: "https://chatgpt.com",
            icon: "sparkles",
            themeColor: Color(red: 16 / 255, green: 163 / 255, blue: 127 / 255),
            controlColor: .teal,
            description: "Asisten AI cerdas untuk percakapan & coding",
            openMacroId: "preset.openChatGPT",
            shortcuts: [
                WebShortcutItem(title: "Obrolan Baru (New Chat)", hotkeyDisplay: "⌘ ⇧ O", icon: "plus.bubble.fill", keyCode: 31, modifiers: [.cmd, .shift], description: "Mulai percakapan baru dengan AI"),
                WebShortcutItem(title: "Salin Jawaban Terakhir", hotkeyDisplay: "⌘ ⇧ C", icon: "doc.on.doc.fill", keyCode: 8, modifiers: [.cmd, .shift], description: "Salin output kode atau teks terbaru"),
                WebShortcutItem(title: "Fokus Input Teks", hotkeyDisplay: "⇧ Esc", icon: "keyboard.fill", keyCode: 53, modifiers: [.shift], description: "Langsung fokus ke kotak ketik prompt"),
                WebShortcutItem(title: "Buka Modal Shortcut", hotkeyDisplay: "⌘ /", icon: "command", keyCode: 44, modifiers: [.cmd], description: "Tampilkan daftar shortcut resmi AI"),
                WebShortcutItem(title: "Buka ChatGPT", hotkeyDisplay: "⌘ T + URL", icon: "brain.head.profile", macroId: "preset.openChatGPT", description: "Buka portal ChatGPT di browser")
            ]
        ),

        // 5. Twitter / X
        PopularWebSite(
            id: "site.twitter",
            name: "Twitter / X",
            url: "https://x.com",
            icon: "bubble.left.and.bubble.right.fill",
            themeColor: Color(red: 29 / 255, green: 155 / 255, blue: 240 / 255),
            controlColor: .cyan,
            description: "Media sosial linimasa & diskusi trending",
            openMacroId: "preset.openX",
            shortcuts: [
                WebShortcutItem(title: "Tweet / Post Baru", hotkeyDisplay: "N", icon: "square.and.pencil", keyCode: 45, description: "Buka dialog ketik tweet baru"),
                WebShortcutItem(title: "Tweet Berikutnya", hotkeyDisplay: "J", icon: "arrow.down", keyCode: 38, description: "Pindah ke tweet di bawahnya"),
                WebShortcutItem(title: "Tweet Sebelumnya", hotkeyDisplay: "K", icon: "arrow.up", keyCode: 40, description: "Pindah ke tweet di atasnya"),
                WebShortcutItem(title: "Sukai (Like)", hotkeyDisplay: "L", icon: "heart.fill", keyCode: 37, description: "Beri tanda suka pada tweet"),
                WebShortcutItem(title: "Balas (Reply)", hotkeyDisplay: "R", icon: "arrowshape.turn.up.left.fill", keyCode: 15, description: "Balas tweet yang sedang disorot"),
                WebShortcutItem(title: "Repost / Retweet", hotkeyDisplay: "T", icon: "arrow.2.squarepath", keyCode: 17, description: "Buka dialog repost tweet"),
                WebShortcutItem(title: "Buka X (Twitter)", hotkeyDisplay: "⌘ T + URL", icon: "antenna.radiowaves.left.and.right", macroId: "preset.openX", description: "Buka x.com pada tab baru")
            ]
        ),

        // 6. Netflix & Streaming
        PopularWebSite(
            id: "site.netflix",
            name: "Netflix",
            url: "https://netflix.com",
            icon: "film.fill",
            themeColor: Color(red: 229 / 255, green: 9 / 255, blue: 20 / 255),
            controlColor: .red,
            description: "Streaming film & serial televisi",
            openMacroId: "preset.openNetflix",
            shortcuts: [
                WebShortcutItem(title: "Play / Pause", hotkeyDisplay: "Space", icon: "playpause.fill", keyCode: 49, description: "Mulai atau jeda tayangan"),
                WebShortcutItem(title: "Layar Penuh (Fullscreen)", hotkeyDisplay: "F", icon: "arrow.up.left.and.arrow.down.right", keyCode: 3, description: "Masuk atau keluar mode layar penuh"),
                WebShortcutItem(title: "Mute Audio", hotkeyDisplay: "M", icon: "speaker.slash.fill", keyCode: 46, description: "Senyapkan suara film"),
                WebShortcutItem(title: "Mundur 10 Detik", hotkeyDisplay: "←", icon: "backward.fill", keyCode: 123, description: "Ulangi 10 detik sebelumnya"),
                WebShortcutItem(title: "Maju 10 Detik", hotkeyDisplay: "→", icon: "forward.fill", keyCode: 124, description: "Lompati 10 detik berikutnya"),
                WebShortcutItem(title: "Lewati Intro (Skip)", hotkeyDisplay: "S", icon: "forward.end.fill", keyCode: 1, description: "Langsung lewati intro atau rekap"),
                WebShortcutItem(title: "Buka Netflix", hotkeyDisplay: "⌘ T + URL", icon: "tv.fill", macroId: "preset.openNetflix", description: "Buka Netflix di browser Mac")
            ]
        ),

        // 7. Spotify Web
        PopularWebSite(
            id: "site.spotify",
            name: "Spotify Web",
            url: "https://open.spotify.com",
            icon: "waveform",
            themeColor: Color(red: 30 / 255, green: 215 / 255, blue: 96 / 255),
            controlColor: .green,
            description: "Pemutar musik & podcast web",
            openMacroId: "preset.openSpotify",
            shortcuts: [
                WebShortcutItem(title: "Play / Pause", hotkeyDisplay: "Space", icon: "playpause.fill", keyCode: 49, description: "Putar atau jeda lagu"),
                WebShortcutItem(title: "Lagu Berikutnya", hotkeyDisplay: "⌘ →", icon: "forward.fill", keyCode: 124, modifiers: [.cmd], description: "Pindah ke lagu selanjutnya"),
                WebShortcutItem(title: "Lagu Sebelumnya", hotkeyDisplay: "⌘ ←", icon: "backward.fill", keyCode: 123, modifiers: [.cmd], description: "Ulangi dari awal atau lagu sebelumnya"),
                WebShortcutItem(title: "Cari Musik", hotkeyDisplay: "⌘ K", icon: "magnifyingglass", keyCode: 40, modifiers: [.cmd], description: "Fokus ke pencarian lagu & artis"),
                WebShortcutItem(title: "Buka Spotify Web", hotkeyDisplay: "⌘ T + URL", icon: "music.note.list", macroId: "preset.openSpotify", description: "Luncurkan pemutar web Spotify")
            ]
        ),

        // 8. Reddit
        PopularWebSite(
            id: "site.reddit",
            name: "Reddit",
            url: "https://reddit.com",
            icon: "flame.fill",
            themeColor: Color(red: 255 / 255, green: 69 / 255, blue: 0 / 255),
            controlColor: .orange,
            description: "Komunitas diskusi & forum internet",
            openMacroId: "preset.openReddit",
            shortcuts: [
                WebShortcutItem(title: "Postingan Berikutnya", hotkeyDisplay: "J", icon: "arrow.down", keyCode: 38, description: "Pindah ke thread / posting berikutnya"),
                WebShortcutItem(title: "Postingan Sebelumnya", hotkeyDisplay: "K", icon: "arrow.up", keyCode: 40, description: "Pindah ke thread sebelumnya"),
                WebShortcutItem(title: "Buka Komentar", hotkeyDisplay: "C", icon: "bubble.left.and.bubble.right.fill", keyCode: 8, description: "Masuk ke halaman komentar posting"),
                WebShortcutItem(title: "Upvote", hotkeyDisplay: "A", icon: "arrow.up.circle.fill", keyCode: 0, description: "Beri suara positif ke posting"),
                WebShortcutItem(title: "Downvote", hotkeyDisplay: "Z", icon: "arrow.down.circle.fill", keyCode: 6, description: "Beri suara negatif ke posting"),
                WebShortcutItem(title: "Buka Reddit", hotkeyDisplay: "⌘ T + URL", icon: "globe.americas.fill", macroId: "preset.openReddit", description: "Buka Reddit di browser")
            ]
        )
    ]
}
