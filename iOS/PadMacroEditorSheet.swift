import SwiftUI

/// Sheet for creating and editing macros on iPad (M4.1).
struct PadMacroEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var macroStore = PadMacroStore.shared

    var existingMacro: PadMacroDefinition?

    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var icon: String = "command.square.fill"
    @State private var steps: [PadMacroStepV2] = []

    // Step addition state
    @State private var selectedActionType: String = "shortcut"
    @State private var inputKeyOrChar: String = "A"
    @State private var delayMsText: String = "100"
    @State private var launchAppText: String = "com.apple.Terminal"
    @State private var textInput: String = ""
    @State private var modCmd = true
    @State private var modOpt = false
    @State private var modCtrl = false
    @State private var modShift = false

    private let availableIcons = [
        "command.square.fill", "doc.on.doc.fill", "arrow.uturn.down.square.fill",
        "plus.square.fill", "terminal.fill", "gearshape.fill", "bolt.fill",
        "sparkles", "play.rectangle.fill", "macwindow"
    ]

    init(existingMacro: PadMacroDefinition? = nil) {
        self.existingMacro = existingMacro
        _name = State(initialValue: existingMacro?.name ?? "")
        _descriptionText = State(initialValue: existingMacro?.description ?? "")
        _icon = State(initialValue: existingMacro?.icon ?? "command.square.fill")
        _steps = State(initialValue: existingMacro?.steps ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Informasi Macro") {
                    TextField("Nama Macro", text: $name)
                    TextField("Deskripsi Singkat", text: $descriptionText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(availableIcons, id: \.self) { (ic: String) in
                                Button {
                                    icon = ic
                                } label: {
                                    Image(systemName: ic)
                                        .font(.system(size: 18))
                                        .frame(width: 38, height: 38)
                                        .background(iconBackground(for: ic))
                                        .foregroundStyle(iconForeground(for: ic))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Daftar Langkah (Maksimal \(PadProtocol.maximumMacroSteps))") {
                    if steps.isEmpty {
                        Text("Belum ada langkah. Tambahkan di bawah.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack {
                                Text("\(index + 1).")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stepLabel(step))
                                        .font(.subheadline.weight(.medium))
                                    Text(stepDetail(step))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .onDelete(perform: deleteStep)
                        .onMove(perform: moveStep)
                    }
                }

                Section("Tambah Langkah Baru") {
                    Picker("Jenis Aksi", selection: $selectedActionType) {
                        Text("Shortcut (Chord)").tag("shortcut")
                        Text("Tekan Tombol").tag("key")
                        Text("Jeda Waktu (Delay)").tag("delay")
                        Text("Ketik Teks").tag("text")
                        Text("Buka Aplikasi").tag("launchApp")
                    }

                    switch selectedActionType {
                    case "shortcut", "key":
                        HStack {
                            Text("Karakter / Huruf:")
                            TextField("Contoh: C", text: $inputKeyOrChar)
                                .textInputAutocapitalization(.characters)
                        }
                        if selectedActionType == "shortcut" {
                            Toggle("⌘ Command", isOn: $modCmd)
                            Toggle("⌥ Option", isOn: $modOpt)
                            Toggle("⌃ Control", isOn: $modCtrl)
                            Toggle("⇧ Shift", isOn: $modShift)
                        }

                    case "delay":
                        HStack {
                            Text("Durasi (ms):")
                            TextField("100", text: $delayMsText)
                                .keyboardType(.numberPad)
                        }

                    case "text":
                        TextField("Teks yang diketik otomatis", text: $textInput)

                    case "launchApp":
                        TextField("Nama App / Bundle ID (com.apple.Terminal)", text: $launchAppText)

                    default:
                        EmptyView()
                    }

                    Button {
                        appendStep()
                    } label: {
                        Label("Tambahkan Langkah", systemImage: "plus.circle.fill")
                    }
                    .disabled(steps.count >= PadProtocol.maximumMacroSteps)
                }
            }
            .navigationTitle(existingMacro == nil ? "Buat Macro Baru" : "Edit Macro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        saveMacro()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || steps.isEmpty)
                }
            }
        }
    }

    private func deleteStep(at offsets: IndexSet) {
        steps.remove(atOffsets: offsets)
    }

    private func moveStep(from source: IndexSet, to destination: Int) {
        steps.move(fromOffsets: source, toOffset: destination)
    }

    private func appendStep() {
        guard steps.count < PadProtocol.maximumMacroSteps else { return }

        switch selectedActionType {
        case "shortcut":
            let key = resolveKeyCode(inputKeyOrChar)
            var mods: [PadModifierFlagV2] = []
            if modCmd { mods.append(.cmd) }
            if modOpt { mods.append(.alt) }
            if modCtrl { mods.append(.ctrl) }
            if modShift { mods.append(.shift) }
            let step = PadMacroStepV2(action: "shortcut", keyCode: key, modifiers: mods, text: nil, delayMs: nil)
            steps.append(step)

        case "key":
            let key = resolveKeyCode(inputKeyOrChar)
            let step = PadMacroStepV2(action: "key", keyCode: key, modifiers: nil, text: nil, delayMs: nil)
            steps.append(step)

        case "delay":
            let ms = Int(delayMsText) ?? 100
            let step = PadMacroStepV2(action: "delay", keyCode: nil, modifiers: nil, text: nil, delayMs: ms)
            steps.append(step)

        case "text":
            guard !textInput.isEmpty else { return }
            let step = PadMacroStepV2(action: "text", keyCode: nil, modifiers: nil, text: textInput, delayMs: nil)
            steps.append(step)
            textInput = ""

        case "launchApp":
            guard !launchAppText.isEmpty else { return }
            let step = PadMacroStepV2(action: "launchApp", keyCode: nil, modifiers: nil, text: launchAppText, delayMs: nil)
            steps.append(step)

        default:
            break
        }
    }

    private func saveMacro() {
        let macroId = existingMacro?.id ?? UUID().uuidString
        let def = PadMacroDefinition(
            id: macroId,
            name: name.trimmingCharacters(in: .whitespaces),
            description: descriptionText.trimmingCharacters(in: .whitespaces),
            icon: icon,
            steps: steps
        )
        macroStore.addOrUpdateMacro(def)
    }

    private func stepLabel(_ step: PadMacroStepV2) -> String {
        switch step.action {
        case "shortcut": return "Shortcut Chord"
        case "key": return "Tekan Tombol"
        case "delay": return "Jeda Waktu"
        case "text": return "Ketik Teks"
        case "launchApp": return "Buka Aplikasi"
        default: return step.action
        }
    }

    private func stepDetail(_ step: PadMacroStepV2) -> String {
        switch step.action {
        case "shortcut":
            let mods = (step.modifiers ?? []).map { $0.rawValue }.joined(separator: " + ")
            return "\(mods) + KeyCode \(step.keyCode ?? 0)"
        case "key":
            return "KeyCode \(step.keyCode ?? 0)"
        case "delay":
            return "\(step.delayMs ?? 0) ms"
        case "text":
            return "\"\(step.text ?? "")\""
        case "launchApp":
            return step.text ?? ""
        default:
            return ""
        }
    }

    private func resolveKeyCode(_ charStr: String) -> UInt16 {
        guard let first = charStr.uppercased().first else { return 0 }
        switch first {
        case "A": return PadVirtualKey.a.rawValue
        case "B": return PadVirtualKey.b.rawValue
        case "C": return PadVirtualKey.c.rawValue
        case "D": return PadVirtualKey.d.rawValue
        case "E": return PadVirtualKey.e.rawValue
        case "F": return PadVirtualKey.f.rawValue
        case "G": return PadVirtualKey.g.rawValue
        case "H": return PadVirtualKey.h.rawValue
        case "I": return PadVirtualKey.i.rawValue
        case "J": return PadVirtualKey.j.rawValue
        case "K": return PadVirtualKey.k.rawValue
        case "L": return PadVirtualKey.l.rawValue
        case "M": return PadVirtualKey.m.rawValue
        case "N": return PadVirtualKey.n.rawValue
        case "O": return PadVirtualKey.o.rawValue
        case "P": return PadVirtualKey.p.rawValue
        case "Q": return PadVirtualKey.q.rawValue
        case "R": return PadVirtualKey.r.rawValue
        case "S": return PadVirtualKey.s.rawValue
        case "T": return PadVirtualKey.t.rawValue
        case "U": return PadVirtualKey.u.rawValue
        case "V": return PadVirtualKey.v.rawValue
        case "W": return PadVirtualKey.w.rawValue
        case "X": return PadVirtualKey.x.rawValue
        case "Y": return PadVirtualKey.y.rawValue
        case "Z": return PadVirtualKey.z.rawValue
        default: return PadVirtualKey.a.rawValue
        }
    }

    private func iconBackground(for ic: String) -> Color {
        icon == ic ? Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255) : Color.white.opacity(0.1)
    }

    private func iconForeground(for ic: String) -> Color {
        icon == ic ? Color.white : Color.secondary
    }
}
