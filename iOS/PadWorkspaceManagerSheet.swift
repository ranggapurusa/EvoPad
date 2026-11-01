import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

// MARK: - FileDocument Wrapper for JSON Export (M5.4)

struct WorkspaceJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents else {
            throw WorkspaceImportError.emptyPayload
        }
        self.data = fileData
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// M5.1 & M5.4 — Workspace Manager & Import/Export Backup sheet.
struct PadWorkspaceManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var workspaceStore: PadWorkspaceStore

    // Create / Edit workspace state
    @State private var showingCreateSheet = false
    @State private var editingWorkspace: Workspace?
    @State private var workspaceNameInput = ""
    @State private var workspaceIconInput = "square.grid.2x2.fill"
    @State private var workspaceColorInput: ControlColor = .indigo

    // Export / Import state (M5.4)
    @State private var exportDocument: WorkspaceJSONDocument?
    @State private var exportFilename: String = "evopad-workspace.json"
    @State private var isExportingFile = false
    @State private var isImportingFile = false
    @State private var showingPasteImportSheet = false
    @State private var pastedJSONText: String = ""

    // Conflict resolution state
    @State private var pendingImportPreview: WorkspaceImportPreview?
    @State private var showingConflictDialog = false
    @State private var statusBannerMessage: String?
    @State private var statusBannerIsError = false

    private static let workspaceIcons: [String] = [
        "sparkles.rectangle.stack.fill", "chevron.left.forwardslash.chevron.right",
        "paintbrush.pointed.fill", "doc.text.fill", "play.tv.fill",
        "square.grid.2x2.fill", "laptopcomputer", "terminal.fill",
        "music.note.tv.fill", "camera.metering.matrix", "gamecontroller.fill", "briefcase.fill"
    ]

    var body: some View {
        NavigationStack {
            List {
                if let statusBannerMessage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: statusBannerIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(statusBannerIsError ? .red : .green)
                            Text(statusBannerMessage)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(statusBannerIsError ? .red : .primary)
                            Spacer()
                            Button {
                                self.statusBannerMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    ForEach(workspaceStore.workspaces) { ws in
                        workspaceRow(ws)
                    }
                } header: {
                    HStack {
                        Text("Daftar Workspace (\(workspaceStore.workspaces.count))")
                        Spacer()
                        Button {
                            workspaceNameInput = ""
                            workspaceIconInput = "square.grid.2x2.fill"
                            workspaceColorInput = .indigo
                            editingWorkspace = nil
                            showingCreateSheet = true
                        } label: {
                            Label("Workspace Baru", systemImage: "plus.circle.fill")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }

                Section("Pengaturan Workspace Aktif") {
                    let active = workspaceStore.activeWorkspace
                    Toggle(
                        "Getaran Haptic Saat Tombol Ditekan",
                        isOn: Binding(
                            get: { active.settings.hapticFeedback },
                            set: { newVal in
                                var s = active.settings
                                s.hapticFeedback = newVal
                                workspaceStore.updateWorkspaceMetadata(id: active.id, name: active.name, settings: s)
                            }
                        )
                    )
                    Toggle(
                        "Tampilkan Badge Shortcut / Tipe Action",
                        isOn: Binding(
                            get: { active.settings.showShortcutSubtitles },
                            set: { newVal in
                                var s = active.settings
                                s.showShortcutSubtitles = newVal
                                workspaceStore.updateWorkspaceMetadata(id: active.id, name: active.name, settings: s)
                            }
                        )
                    )
                    Toggle(
                        "Mode Ergonomis Satu Tangan (Compact)",
                        isOn: Binding(
                            get: { active.settings.oneHandedCompactMode },
                            set: { newVal in
                                var s = active.settings
                                s.oneHandedCompactMode = newVal
                                workspaceStore.updateWorkspaceMetadata(id: active.id, name: active.name, settings: s)
                            }
                        )
                    )
                    Toggle(
                        "Konfirmasi Sebelum Sleep / Lock Mac",
                        isOn: Binding(
                            get: { active.settings.confirmDestructiveSystemActions },
                            set: { newVal in
                                var s = active.settings
                                s.confirmDestructiveSystemActions = newVal
                                workspaceStore.updateWorkspaceMetadata(id: active.id, name: active.name, settings: s)
                            }
                        )
                    )
                }

                Section("Import, Export & Backup Konfigurasi (M5.4)") {
                    Button {
                        exportSingleWorkspace(workspaceStore.activeWorkspace)
                    } label: {
                        Label("Export Workspace Aktif (\(workspaceStore.activeWorkspace.name))", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        exportFullBackup()
                    } label: {
                        Label("Backup Seluruh Workspace (JSON)", systemImage: "externaldrive.badge.checkmark")
                    }

                    Button {
                        isImportingFile = true
                    } label: {
                        Label("Import / Restore dari File JSON", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        if let data = try? workspaceStore.exportWorkspaceData(id: workspaceStore.activeWorkspaceId),
                           let str = String(data: data, encoding: .utf8) {
                            pastedJSONText = str
                        } else {
                            pastedJSONText = ""
                        }
                        showingPasteImportSheet = true
                    } label: {
                        Label("Inspeksi / Import via Teks JSON", systemImage: "doc.badge.gearshape")
                    }

                    Button {
                        let results = PadWorkspaceStore.runSelfChecks()
                        showStatus(results.joined(separator: " • "), isError: false)
                    } label: {
                        Label("Jalankan Diagnostik & Self-Check M5", systemImage: "checkmark.shield.fill")
                    }
                }
            }
            .navigationTitle("Manajemen Workspace")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .fileExporter(
                isPresented: $isExportingFile,
                document: exportDocument,
                contentType: .json,
                defaultFilename: exportFilename
            ) { result in
                switch result {
                case .success:
                    showStatus("Berhasil mengekspor file JSON (\(exportFilename)).", isError: false)
                case .failure(let error):
                    showStatus("Gagal mengekspor: \(error.localizedDescription)", isError: true)
                }
            }
            .fileImporter(
                isPresented: $isImportingFile,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleFileImportResult(result)
            }
            .confirmationDialog(
                "Konflik Nama / ID Workspace Ditemukan",
                isPresented: $showingConflictDialog,
                titleVisibility: .visible
            ) {
                Button("Simpan Keduanya (Buat Salinan Baru)") {
                    if let preview = pendingImportPreview {
                        let count = workspaceStore.applyImport(preview, policy: .keepBoth)
                        showStatus("Berhasil mengimpor \(count) workspace tanpa menimpa data lama.", isError: false)
                        pendingImportPreview = nil
                    }
                }
                Button("Lewati Workspace yang Bentrok") {
                    if let preview = pendingImportPreview {
                        let count = workspaceStore.applyImport(preview, policy: .skipConflicting)
                        showStatus("Mengimpor \(count) workspace baru (yang bentrok dilewati).", isError: false)
                        pendingImportPreview = nil
                    }
                }
                Button("Timpa Workspace yang Sudah Ada", role: .destructive) {
                    if let preview = pendingImportPreview {
                        let count = workspaceStore.applyImport(preview, policy: .overwriteApproved)
                        showStatus("Berhasil memperbarui/menimpa \(count) workspace.", isError: false)
                        pendingImportPreview = nil
                    }
                }
                Button("Batal", role: .cancel) {
                    pendingImportPreview = nil
                }
            } message: {
                if let preview = pendingImportPreview {
                    Text("Workspace berikut sudah ada: \(preview.conflictingWorkspaceNames.joined(separator: ", ")). Pilih cara menangani konflik:")
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                workspaceMetadataSheet
            }
            .sheet(isPresented: $showingPasteImportSheet) {
                jsonTextImportSheet
            }
        }
    }

    @ViewBuilder
    private func workspaceRow(_ ws: Workspace) -> some View {
        let isActive = (ws.id == workspaceStore.activeWorkspaceId)
        HStack(spacing: 12) {
            Button {
                workspaceStore.switchWorkspace(to: ws.id)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: ws.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(ws.accentColor.swiftUIColor)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(ws.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            if ws.isDefault {
                                Text("DEFAULT")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.indigo.opacity(0.2)))
                                    .foregroundStyle(.indigo)
                            }
                            if ws.isPreset {
                                Text("PRESET")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("\(ws.layout.items.count) tombol • Grid \(ws.layout.columns)×\(ws.layout.rows)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Menu {
                Button {
                    workspaceStore.switchWorkspace(to: ws.id)
                } label: {
                    Label("Aktifkan Workspace", systemImage: "bolt.fill")
                }

                Button {
                    workspaceStore.setDefaultWorkspace(id: ws.id)
                    showStatus("'\(ws.name)' dijadikan workspace default.", isError: false)
                } label: {
                    Label("Jadikan Default", systemImage: "star.fill")
                }

                Button {
                    editingWorkspace = ws
                    workspaceNameInput = ws.name
                    workspaceIconInput = ws.icon
                    workspaceColorInput = ws.accentColor
                    showingCreateSheet = true
                } label: {
                    Label("Ubah Nama / Ikon / Warna", systemImage: "pencil")
                }

                Button {
                    if let dup = workspaceStore.duplicateWorkspace(id: ws.id) {
                        showStatus("Workspace diduplikasi sebagai '\(dup.name)'.", isError: false)
                    }
                } label: {
                    Label("Duplikat Workspace", systemImage: "plus.square.on.square")
                }

                Button {
                    exportSingleWorkspace(ws)
                } label: {
                    Label("Export JSON", systemImage: "square.and.arrow.up")
                }

                if ws.isPreset {
                    Button {
                        workspaceStore.resetPresetWorkspace(id: ws.id)
                        showStatus("Preset '\(ws.name)' dikembalikan ke bawaan.", isError: false)
                    } label: {
                        Label("Reset Preset ke Awal", systemImage: "arrow.counterclockwise")
                    }
                }

                if workspaceStore.workspaces.count > 1 {
                    Divider()
                    Button(role: .destructive) {
                        let deletedName = ws.name
                        if workspaceStore.deleteWorkspace(id: ws.id) {
                            showStatus("Workspace '\(deletedName)' dihapus.", isError: false)
                        }
                    } label: {
                        Label("Hapus Workspace", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    private var workspaceMetadataSheet: some View {
        NavigationStack {
            Form {
                Section("Identitas Workspace") {
                    TextField("Nama Workspace", text: $workspaceNameInput)

                    Picker("Warna Aksen", selection: $workspaceColorInput) {
                        ForEach(ControlColor.allCases) { col in
                            Text(col.title).tag(col)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ikon Workspace")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                            ForEach(Self.workspaceIcons, id: \.self) { sym in
                                Button {
                                    workspaceIconInput = sym
                                } label: {
                                    Image(systemName: sym)
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(width: 36, height: 36)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(workspaceIconInput == sym ? workspaceColorInput.swiftUIColor.opacity(0.25) : Color.secondary.opacity(0.1))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle(editingWorkspace == nil ? "Buat Workspace Baru" : "Edit Workspace")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { showingCreateSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        if let editing = editingWorkspace {
                            workspaceStore.updateWorkspaceMetadata(
                                id: editing.id,
                                name: workspaceNameInput,
                                icon: workspaceIconInput,
                                accentColor: workspaceColorInput
                            )
                        } else {
                            workspaceStore.createWorkspace(
                                name: workspaceNameInput,
                                icon: workspaceIconInput,
                                accentColor: workspaceColorInput
                            )
                        }
                        showingCreateSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var jsonTextImportSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Salin JSON konfigurasi untuk backup, atau tempel JSON workspace untuk diimpor dan divalidasi:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $pastedJSONText)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                HStack {
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = pastedJSONText
                        #endif
                        showStatus("JSON disalin ke Clipboard.", isError: false)
                    } label: {
                        Label("Salin JSON", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        let rawData = Data(pastedJSONText.utf8)
                        showingPasteImportSheet = false
                        processIncomingImportData(rawData)
                    } label: {
                        Label("Validasi & Import JSON", systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("JSON Konfigurasi Workspace")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { showingPasteImportSheet = false }
                }
            }
        }
    }

    // MARK: - Import / Export Helpers

    private func exportSingleWorkspace(_ ws: Workspace) {
        do {
            let data = try workspaceStore.exportWorkspaceData(id: ws.id)
            let sanitized = ws.name.lowercased().replacingOccurrences(of: " ", with: "-")
            exportFilename = "evopad-workspace-\(sanitized).json"
            exportDocument = WorkspaceJSONDocument(data: data)
            isExportingFile = true
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    private func exportFullBackup() {
        do {
            let data = try workspaceStore.exportAllWorkspacesData()
            exportFilename = "evopad-workspaces-backup-v\(PadWorkspaceSchema.currentVersion).json"
            exportDocument = WorkspaceJSONDocument(data: data)
            isExportingFile = true
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            showStatus("Gagal membuka file: \(error.localizedDescription)", isError: true)
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            guard let data = try? Data(contentsOf: url) else {
                showStatus("Tidak dapat membaca isi file JSON.", isError: true)
                return
            }
            processIncomingImportData(data)
        }
    }

    private func processIncomingImportData(_ data: Data) {
        switch workspaceStore.validateImportData(data) {
        case .failure(let error):
            showStatus(error.localizedDescription, isError: true)
        case .success(let preview):
            if preview.hasConflicts {
                pendingImportPreview = preview
                showingConflictDialog = true
            } else {
                let count = workspaceStore.applyImport(preview, policy: .keepBoth)
                let note = preview.hadCollisionRepairs ? " (posisi tombol yang bertabrakan telah dirapikan otomatis)" : ""
                showStatus("Berhasil mengimpor \(count) workspace\(note).", isError: false)
            }
        }
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusBannerMessage = message
        statusBannerIsError = isError
    }
}
