import Foundation

protocol PasteboardReading {
    var changeCount: Int { get }
    func plainText() -> String?
}

struct ClosurePasteboardReader: PasteboardReading {
    private let read: () -> String?
    private let readChangeCount: () -> Int

    init(changeCount: @escaping () -> Int = { 0 }, _ read: @escaping () -> String?) {
        self.read = read
        self.readChangeCount = changeCount
    }

    var changeCount: Int {
        readChangeCount()
    }

    func plainText() -> String? {
        read()
    }
}

import AppKit

struct SystemPasteboardReader: PasteboardReading {
    var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    func plainText() -> String? {
        NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
