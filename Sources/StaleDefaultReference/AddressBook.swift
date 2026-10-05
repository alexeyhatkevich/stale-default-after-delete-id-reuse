/// One row of the "Saved addresses" screen.
public struct AddressRow: Equatable, Sendable {
    public let address: Address
    /// Whether the row shows the "Default" badge.
    public let showsDefaultBadge: Bool
}

/// The screen-facing API both clients share.
public protocol AddressBook {
    var server: FakeAddressServer { get }
    /// What the list UI renders.
    func rows() -> [AddressRow]
    /// The user swiped "Delete" on a row.
    func delete(id: Int) throws
    /// The user saved a new address. The app then asks "Make this your default?".
    func add(_ draft: AddressDraft) -> Address
    /// The user's answer to "Make this your default?".
    func answerMakeDefault(for address: Address, makeDefault: Bool) throws
}

extension AddressBook {
    public func add(_ draft: AddressDraft) -> Address { server.add(draft) }

    public func answerMakeDefault(for address: Address, makeDefault: Bool) throws {
        // "Not now" sends nothing — the user did not ask for a change.
        if makeDefault { try server.setDefault(id: address.id) }
    }

    /// The address the UI badges as default, if any.
    public func badgedDefault() -> Address? {
        rows().first(where: \.showsDefaultBadge)?.address
    }
}

// MARK: - Naive

/// Deletes without touching the default, and hides the dangling reference
/// behind a display fallback ("no match? badge the first address").
public struct NaiveAddressBook: AddressBook {
    public let server: FakeAddressServer
    public init(server: FakeAddressServer) { self.server = server }

    public func rows() -> [AddressRow] {
        let addresses = server.list()
        let defaultId = server.defaultAddressId
        let hasMatch = addresses.contains { $0.id == defaultId }
        // Display fallback: if the stored default matches nothing, badge the first real
        // address. It looks right on screen, but the server still holds the stale id.
        let fallbackId = hasMatch ? nil : addresses.first(where: { !$0.isSynthetic })?.id
        return addresses.map { address in
            AddressRow(address: address,
                       showsDefaultBadge: address.id == defaultId || address.id == fallbackId)
        }
    }

    public func delete(id: Int) throws {
        try server.delete(id: id)   // DELETE /addresses/{id} — and that's it
    }
}

// MARK: - Fixed

/// Keeps the server's default consistent in the same flow as the delete,
/// and renders the badge strictly from server state.
public struct FixedAddressBook: AddressBook {
    public let server: FakeAddressServer
    public init(server: FakeAddressServer) { self.server = server }

    public func rows() -> [AddressRow] {
        let defaultId = server.defaultAddressId
        // No fallback: if the server has no default, nothing is badged.
        return server.list().map { AddressRow(address: $0, showsDefaultBadge: $0.id == defaultId) }
    }

    public func delete(id: Int) throws {
        // 1. Capture the fact BEFORE the delete — afterwards there is nothing to compare with.
        let wasDefault = server.defaultAddressId == id

        // 2. The delete itself. If it throws, we change nothing else.
        try server.delete(id: id)

        // 3. Repair every reference to the deleted id in the same flow.
        guard wasDefault else { return }
        let successor = server.list().first { !$0.isSynthetic && $0.id != id }
        try server.setDefault(id: successor?.id)   // nil -> DELETE /addresses/default
    }
}
