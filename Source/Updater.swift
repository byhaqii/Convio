import AppKit
import Foundation
import Observation

@Observable @MainActor final class Updater {
    var available: UpdateRelease?
    var checking = false
    var installing = false
    var windowBusy = false
    var queuedFiles = 0
    var status = ""
    private let dragWheel: DragWheelController

    init(dragWheel: DragWheelController) { self.dragWheel = dragWheel }

    func check(manual: Bool) async {
        guard !checking, !installing else { return }
        checking = true
        defer { checking = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/byhaqii/Convio/releases/latest")!,
                                     cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Convio", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !installing else { return }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError("GitHub could not check for updates. Try again later.")
            }
            guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
                throw UpdateError("Convio's installed version could not be read.")
            }
            available = try UpdateRelease.parse(data, currentVersion: version)
            status = available.map { "Convio \($0.version) is available" } ?? "Convio is up to date"
            if manual { showMessage("Convio Updates", status) }
        } catch {
            if manual { showMessage("Could not check for updates", error.localizedDescription) }
        }
    }

    func install() async {
        guard let release = available, !installing else { return }
        var work: URL?
        var handedOff = false
        defer {
            if !handedOff {
                if let work { try? FileManager.default.removeItem(at: work) }
                installing = false
                dragWheel.updating = false
            }
        }
        do {
            try UpdateSafety.requireIdle(windowBusy: windowBusy, wheelBusy: dragWheel.isProcessing)
            let alert = NSAlert()
            alert.messageText = "Update to Convio \(release.version)?"
            alert.informativeText = "Convio will download the update and restart. Your original files and conversion results stay unchanged."
                + (queuedFiles > 0 ? " The current list of \(queuedFiles) files will be cleared." : "")
            alert.addButton(withTitle: "Update & Restart")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try UpdateSafety.requireIdle(windowBusy: windowBusy, wheelBusy: dragWheel.isProcessing)
            installing = true
            dragWheel.updating = true
            status = "Downloading update…"
            let destination = Bundle.main.bundleURL.resolvingSymlinksInPath()
            guard destination.pathExtension == "app" else { throw UpdateError("Run Convio from an installed app bundle to update.") }
            let directory = destination.deletingLastPathComponent().appendingPathComponent(".Convio-update-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                 attributes: [.posixPermissions: 0o700])
            work = directory
            let request = URLRequest(url: release.url, timeoutInterval: 120)
            let (download, response) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: download) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("The update could not be downloaded.") }
            try UpdateValidation.verifyArchive(download, sha256: release.sha256)
            try UpdateValidation.run("/usr/bin/ditto", ["-x", "-k", download.path, directory.path])
            let staged = directory.appendingPathComponent("Convio.app")
            try UpdateValidation.verifyBundle(staged, version: release.version)
            try UpdateSafety.requireIdle(windowBusy: windowBusy, wheelBusy: dragWheel.isProcessing)
            guard let resource = Bundle.main.url(forResource: "update-app", withExtension: "sh") else {
                throw UpdateError("The update helper is missing. Reinstall Convio using Terminal.")
            }
            let helper = directory.appendingPathComponent("update-app.sh")
            try FileManager.default.copyItem(at: resource, to: helper)
            let log = directory.appendingPathComponent("update.log")
            guard FileManager.default.createFile(atPath: log.path, contents: nil) else { throw UpdateError("Could not create the update log.") }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [helper.path, String(ProcessInfo.processInfo.processIdentifier), destination.path, staged.path]
            process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory()]
            let output = try FileHandle(forWritingTo: log)
            defer { try? output.close() }
            process.standardOutput = output
            process.standardError = output
            process.standardInput = FileHandle.nullDevice
            try process.run()
            handedOff = true
            NSApp.terminate(nil)
        } catch {
            status = "Update failed"
            showMessage("Convio was not updated", error.localizedDescription)
        }
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
