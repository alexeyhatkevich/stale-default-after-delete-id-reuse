import Testing
@testable import StaleDefaultReference

let home = AddressDraft(name: "Home", street: "12 Elm Street", city: "Springfield")
let office = AddressDraft(name: "Office", street: "500 Main Ave", city: "Springfield")
let parents = AddressDraft(name: "Parents", street: "7 Oak Lane", city: "Shelbyville")

/// Home (default), Office, Parents — plus the server's synthetic "Pick up in store" entry.
func seededServer() throws -> FakeAddressServer {
    let server = FakeAddressServer()
    let first = server.add(home)
    server.add(office)
    server.add(parents)
    try server.setDefault(id: first.id)
    return server
}

/// The exact user story: delete the default, re-add the same address, answer "Not now".
func deleteDefaultThenReAddAndDecline(_ book: some AddressBook) throws -> Address {
    let homeId = FakeAddressServer.contentId(for: home)
    try book.delete(id: homeId)
    let readded = book.add(home)
    try book.answerMakeDefault(for: readded, makeDefault: false)
    return readded
}

@Suite("Backend contract")
struct BackendContractTests {
    @Test("Re-adding the same content returns the same id")
    func test_server_reAddingSameAddressReturnsSameId() throws {
        // Proves the precondition: ids are content-derived, so a deleted id comes back.
        let server = FakeAddressServer()
        let firstId = server.add(home).id
        try server.delete(id: firstId)
        #expect(server.add(home).id == firstId)
    }

    @Test("DELETE leaves the default pointing at the deleted id")
    func test_server_deleteDoesNotClearDefault() throws {
        // Proves the second precondition: the default is stored separately and survives the delete.
        let server = try seededServer()
        let homeId = FakeAddressServer.contentId(for: home)
        try server.delete(id: homeId)
        #expect(server.defaultAddressId == homeId)
        #expect(!server.list().contains { $0.id == homeId })
    }
}

@Suite("Naive client")
struct NaiveTests {
    @Test("Display fallback hides the dangling default")
    func test_naive_displayFallbackHidesDanglingDefault() throws {
        // After deleting the default, the UI badges Office — but the server still says Home.
        let server = try seededServer()
        let book = NaiveAddressBook(server: server)
        try book.delete(id: FakeAddressServer.contentId(for: home))
        #expect(book.badgedDefault()?.name == "Office")
        #expect(server.defaultAddressId == FakeAddressServer.contentId(for: home))
    }

    @Test("Re-added address becomes default although the user said Not now")
    func test_naive_reAddedAddressSilentlyBecomesDefault() throws {
        // The bug: the stale default id matches the re-added address again.
        let server = try seededServer()
        let book = NaiveAddressBook(server: server)
        let readded = try deleteDefaultThenReAddAndDecline(book)
        #expect(server.defaultAddressId == readded.id)
        #expect(book.badgedDefault() == readded)
    }

    @Test("Naive client never sends a default update on delete")
    func test_naive_deleteSendsOnlyTheDelete() throws {
        // Documents the missing request.
        let server = try seededServer()
        let before = server.requestLog.count
        try NaiveAddressBook(server: server).delete(id: FakeAddressServer.contentId(for: home))
        #expect(Array(server.requestLog.dropFirst(before)) == ["DELETE /addresses/\(FakeAddressServer.contentId(for: home))"])
    }
}

@Suite("Fixed client")
struct FixedTests {
    @Test("Re-added address respects Not now")
    func test_fixed_reAddedAddressIsNotDefaultAfterDecline() throws {
        // The fix: the default was moved away from the deleted id, so nothing re-attaches.
        let server = try seededServer()
        let book = FixedAddressBook(server: server)
        let readded = try deleteDefaultThenReAddAndDecline(book)
        #expect(server.defaultAddressId != readded.id)
        #expect(book.rows().first { $0.address == readded }?.showsDefaultBadge == false)
    }

    @Test("Deleting the default promotes the next real address on the server")
    func test_fixed_deletingDefaultPromotesNextRealAddress() throws {
        // Badge and server agree: Office is the default in both places.
        let server = try seededServer()
        let book = FixedAddressBook(server: server)
        try book.delete(id: FakeAddressServer.contentId(for: home))
        #expect(server.defaultAddressId == FakeAddressServer.contentId(for: office))
        #expect(book.badgedDefault()?.name == "Office")
    }

    @Test("The synthetic id-0 entry is never promoted")
    func test_fixed_neverPromotesSyntheticEntry() throws {
        // The pickup entry is listed first; a plain `list().first` would have picked it.
        let server = try seededServer()
        let book = FixedAddressBook(server: server)
        #expect(server.list().first?.id == FakeAddressServer.pickupId)
        try book.delete(id: FakeAddressServer.contentId(for: home))
        try book.delete(id: FakeAddressServer.contentId(for: office))
        #expect(server.defaultAddressId == FakeAddressServer.contentId(for: parents))
        #expect(server.defaultAddressId != FakeAddressServer.pickupId)
    }

    @Test("Deleting the last real address clears the default")
    func test_fixed_deletingLastAddressClearsDefault() throws {
        // Only the synthetic entry remains, so the default becomes nil — not 0, not stale.
        let server = FakeAddressServer()
        let book = FixedAddressBook(server: server)
        let only = server.add(home)
        try server.setDefault(id: only.id)
        try book.delete(id: only.id)
        #expect(server.requestLog.last == "DELETE /addresses/default")
        #expect(server.defaultAddressId == nil)
        #expect(book.badgedDefault() == nil)
    }

    @Test("Deleting a non-default address leaves the default alone")
    func test_fixed_deletingNonDefaultDoesNotTouchDefault() throws {
        // The repair only runs when the deleted address WAS the default.
        let server = try seededServer()
        let before = server.requestLog.count
        try FixedAddressBook(server: server).delete(id: FakeAddressServer.contentId(for: office))
        #expect(server.defaultAddressId == FakeAddressServer.contentId(for: home))
        #expect(!server.requestLog.dropFirst(before).contains { $0.contains("/default") })
    }

    @Test("A failed delete does not move the default")
    func test_fixed_failedDeleteKeepsDefault() throws {
        // The wasDefault flag is captured first, but acted on only after a successful delete.
        let server = try seededServer()
        #expect(throws: AddressServerError.notFound(42)) {
            try FixedAddressBook(server: server).delete(id: 42)
        }
        #expect(server.defaultAddressId == FakeAddressServer.contentId(for: home))
    }
}
