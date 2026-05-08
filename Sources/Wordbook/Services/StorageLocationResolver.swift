import Foundation

struct StorageLocationResolver {
    var explicitDirectory: URL?

    func wordbookDirectory() -> URL {
        if let explicitDirectory {
            return explicitDirectory
        }

        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport.appendingPathComponent("Wordbook", isDirectory: true)
    }
}
