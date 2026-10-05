import Foundation
import Observation
import StaleDefaultReference

enum Mode: String, CaseIterable, Identifiable {
    case naive = "Naive", fixed = "Fixed"
    var id: Self { self }
}

/// Wraps the library's fake server + client so SwiftUI can observe it.
@MainActor @Observable
final class DemoModel {
    static let home = AddressDraft(name: "Home", street: "12 Elm Street", city: "Springfield")
    static let office = AddressDraft(name: "Office", street: "500 Main Ave", city: "Springfield")
    static let parents = AddressDraft(name: "Parents", street: "7 Oak Lane", city: "Shelbyville")

    var mode: Mode = .naive { didSet { reset() } }
    private(set) var rows: [AddressRow] = []
    private(set) var serverDefaultId: Int?
    private(set) var log: [String] = []
    /// Set after "Re-add Home" so the view can show the "Make this your default?" prompt.
    var pendingPrompt: Address?

    private var server = FakeAddressServer()
    private var book: any AddressBook { mode == .naive ? NaiveAddressBook(server: server) : FixedAddressBook(server: server) }

    init() { reset() }

    func reset() {
        server = FakeAddressServer()
        let first = server.add(Self.home)
        server.add(Self.office)
        server.add(Self.parents)
        try? server.setDefault(id: first.id)
        log = ["Seeded Home (default), Office, Parents"]
        pendingPrompt = nil
        refresh()
    }

    var homeIsListed: Bool { rows.contains { $0.address.name == "Home" } }

    func delete(_ address: Address) {
        do {
            try book.delete(id: address.id)
            log.append("Deleted \(address.name)")
        } catch {
            log.append("Delete failed: \(error)")
        }
        refresh()
    }

    func reAddHome() {
        let address = book.add(Self.home)
        log.append("Re-added Home (id \(address.id)) — same id as before")
        pendingPrompt = address
        refresh()
    }

    func answer(makeDefault: Bool) {
        guard let address = pendingPrompt else { return }
        pendingPrompt = nil
        try? book.answerMakeDefault(for: address, makeDefault: makeDefault)
        log.append(makeDefault ? "Answered \"Make default\"" : "Answered \"Not now\"")
        refresh()
    }

    func name(for id: Int?) -> String {
        guard let id else { return "none" }
        let match = rows.first { $0.address.id == id }?.address.name
        return "\(id) (\(match ?? "points at nothing!"))"
    }

    /// True when the server's default id does not match any listed address.
    var defaultIsDangling: Bool {
        guard let serverDefaultId else { return false }
        return !rows.contains { $0.address.id == serverDefaultId }
    }

    private func refresh() {
        rows = book.rows()
        serverDefaultId = server.defaultAddressId
    }
}
