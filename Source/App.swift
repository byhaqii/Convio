import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let dragWheel = DragWheelController()
    private var converterWindow: NSWindow?

    func showConverter() {
        if converterWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Convy"
            window.contentViewController = NSHostingController(rootView: ContentView(dragWheel: dragWheel))
            window.isReleasedWhenClosed = false
            window.center()
            converterWindow = window
        }
        converterWindow?.deminiaturize(nil)
        converterWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct Item: Identifiable {
    let id = UUID()
    let url: URL
    var status = "Siap"
    var outputs: [URL] = []
}

@main struct ConvyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra("Convy", systemImage: "arrow.triangle.2.circlepath") {
            Button("Open Convy") { delegate.showConverter() }
            Button("Open Wheel") { delegate.dragWheel.openWheel() }
            Divider()
            Button("Quit Convy") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

struct ContentView: View {
    let dragWheel: DragWheelController
    @State private var quickDrag = true
    @State private var items: [Item] = []
    @State private var format = ImageFormat.png
    @State private var quality = 0.85
    @State private var folder: URL?
    @State private var busy = false
    @State private var targeted = false
    @State private var message = ""
    @State private var theme = "Sistem"
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Convy").font(.largeTitle.weight(.semibold))
                    Text("Konversi gambar dan PDF di Mac-mu.").foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Tema", selection: $theme) {
                    Text("Sistem").tag("Sistem"); Text("Terang").tag("Terang"); Text("Gelap").tag("Gelap")
                }.frame(width: 145)
            }
            VStack(spacing: 10) {
                Text(items.isEmpty ? "Tarik file ke sini" : "\(items.count) file dipilih")
                    .font(.title3.weight(.medium))
                Text("JPG, PNG, HEIC, dan PDF").foregroundStyle(.secondary)
                Button("Pilih file…", action: pickFiles).keyboardShortcut("o")
            }
            .frame(maxWidth: .infinity).padding(22)
            .background(targeted ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5])))
            .dropDestination(for: URL.self) { urls, _ in
                guard !busy else { return false }; add(urls); return !urls.isEmpty
            } isTargeted: { targeted = $0 }
            .disabled(busy)

            List {
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.url.lastPathComponent).lineLimit(1).help(item.url.path)
                            Text(item.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        if !item.outputs.isEmpty {
                            Button("Lihat") { NSWorkspace.shared.activateFileViewerSelecting(item.outputs) }
                        }
                        Button("Hapus") { items.removeAll { $0.id == item.id } }.disabled(busy)
                    }.padding(.vertical, 3)
                }
            }.listStyle(.inset).frame(minHeight: 90)
            HStack(spacing: 20) {
                Picker("Format", selection: $format) {
                    ForEach(ImageFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.frame(width: 180)
                if format == .jpg || format == .heic {
                    Slider(value: $quality, in: 0.1...1, step: 0.05) { Text("Kualitas") }
                    Text("\(Int((quality * 100).rounded()))%").monospacedDigit().frame(width: 40)
                }
            }.disabled(busy)
            HStack {
                Button("Folder hasil…", action: pickFolder).disabled(busy)
                Text(folder?.path ?? "Pilih tempat menyimpan hasil").font(.caption).lineLimit(1).truncationMode(.middle)
                    .help(folder?.path ?? "Belum dipilih")
            }
            Text("File asli tetap disimpan. Metadata tidak disalin. Transparansi menjadi putih pada JPG.")
                .font(.caption).foregroundStyle(.secondary)
            Text("PDF ke gambar: setiap halaman menjadi file terpisah, 144 DPI.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Toggle("Shift + tarik file: roda format. Hasil di folder asal.", isOn: $quickDrag)
                    .onChange(of: quickDrag) { _, enabled in dragWheel.enabled = enabled }
                Spacer()
                Button("Buka roda") { dragWheel.openWheel() }
            }
            Divider()
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Text(message).font(.callout).lineLimit(2).textSelection(.enabled)
                Spacer()
                Button("Konversi file", action: run).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return).disabled(items.isEmpty || folder == nil || busy)
            }
        }.padding(24).frame(minWidth: 700, minHeight: 580)
        .preferredColorScheme(theme == "Sistem" ? nil : theme == "Gelap" ? .dark : .light)
    }

    private func add(_ urls: [URL]) {
        guard !busy else { return }
        for url in urls where url.isFileURL && !items.contains(where: { $0.url == url }) {
            items.append(Item(url: url))
        }
        message = ""
    }
    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK { add(panel.urls) }
        }
    }
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.begin { response in
            if response == .OK { folder = panel.url }
        }
    }
    private func run() {
        guard let folder, !busy else { return }
        busy = true
        let selectedFormat = format, selectedQuality = quality
        Task {
            var completed = 0
            for index in items.indices {
                items[index].status = "Mengonversi…"
                message = "Memproses \(index + 1) dari \(items.count)…"
                do {
                    let outputs = try await Converter.convert(items[index].url, to: selectedFormat, quality: selectedQuality, folder: folder)
                    items[index].outputs = outputs
                    items[index].status = "Selesai · \(outputs.count) file hasil"
                    completed += 1
                } catch {
                    items[index].outputs = []
                    items[index].status = "Gagal · \(error.localizedDescription)"
                }
            }
            message = "Selesai: \(completed) berhasil, \(items.count - completed) gagal."
            busy = false
        }
    }
}
