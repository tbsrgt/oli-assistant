import AppKit

// MARK: - Envoyer par mail (fichier ou dossier déposé sur l'encoche)
// Opens a new message in the user's mail app with the file attached; a folder is zipped first.
// Nothing is ever sent by Oli: the user picks the recipient and clicks « Envoyer ».

@MainActor
enum MailShare {
    static func compose(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        let name = url.lastPathComponent
        let folder = isDir.boolValue
        Task.detached(priority: .userInitiated) {
            let attachment = folder ? zip(url) : url
            await MainActor.run { openMail(attachment ?? url, name: name, folder: folder) }
        }
    }

    private static func openMail(_ attachment: URL, name: String, folder: Bool) {
        if let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: [attachment]) {
            service.subject = folder ? "Dossier : \(name)" : name
            service.perform(withItems: [attachment])
        } else {
            // No mail app configured: show the file so it can be dragged into any mail.
            NSWorkspace.shared.activateFileViewerSelecting([attachment])
        }
    }

    /// The file to attach: the file itself, or a fresh .zip of a folder.
    nonisolated static func attachmentFile(for url: URL) async throws -> URL {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard isDir.boolValue else { return url }
        guard let z = await Task.detached(operation: { zip(url) }).value else {
            throw EmailSender.Failure.curl("Le dossier n’a pas pu être compressé.")
        }
        return z
    }

    /// Zips a folder into a temporary .zip (same name), keeping the folder itself at the root.
    nonisolated private static func zip(_ folder: URL) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("oli-mail-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(folder.lastPathComponent + ".zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, dest.path]
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        return p.terminationStatus == 0 ? dest : nil
    }
}
