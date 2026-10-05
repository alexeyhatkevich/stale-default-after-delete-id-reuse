import Foundation

/// A saved shipping address as the server returns it.
public struct Address: Equatable, Sendable {
    public let id: Int
    public let name: String
    public let street: String
    public let city: String

    /// The server prepends a system entry with id 0 ("Pick up in store").
    /// It is listed like an address but it is not one, so it must never become the default.
    public var isSynthetic: Bool { id == FakeAddressServer.pickupId }
}

/// What the client sends to `POST /addresses`.
public struct AddressDraft: Equatable, Sendable {
    public let name: String
    public let street: String
    public let city: String

    public init(name: String, street: String, city: String) {
        self.name = name
        self.street = street
        self.city = city
    }
}

public enum AddressServerError: Error, Equatable {
    case notFound(Int)
}

/// In-memory stand-in for a REST backend with this contract:
///
///     GET    /addresses          -> [Address]   (system "pickup" entry with id 0 first)
///     POST   /addresses          -> Address     (id is derived from the content!)
///     DELETE /addresses/{id}                    (does NOT touch the default)
///     GET    /addresses/default  -> id or null
///     PUT    /addresses/default  {id}  /  DELETE /addresses/default
///
/// Two properties of this backend combine into the bug:
/// 1. `defaultAddressId` is stored separately from the list and is not cleared on delete.
/// 2. Ids are content-derived, so re-adding the same address yields the same id.
public final class FakeAddressServer {
    public static let pickupId = 0

    private var addresses: [Address] = []
    public private(set) var defaultAddressId: Int?

    /// Every request the client made, in order — handy for asserting the call sequence.
    public private(set) var requestLog: [String] = []

    public init() {}

    /// GET /addresses
    public func list() -> [Address] {
        requestLog.append("GET /addresses")
        let pickup = Address(id: Self.pickupId, name: "Pick up in store", street: "", city: "")
        return [pickup] + addresses
    }

    /// POST /addresses — the id is a deterministic function of the content.
    @discardableResult
    public func add(_ draft: AddressDraft) -> Address {
        requestLog.append("POST /addresses")
        let address = Address(id: Self.contentId(for: draft), name: draft.name,
                              street: draft.street, city: draft.city)
        if !addresses.contains(where: { $0.id == address.id }) {
            addresses.append(address)
        }
        return address
    }

    /// DELETE /addresses/{id} — removes the address and nothing else.
    public func delete(id: Int) throws {
        requestLog.append("DELETE /addresses/\(id)")
        guard let index = addresses.firstIndex(where: { $0.id == id }) else {
            throw AddressServerError.notFound(id)
        }
        addresses.remove(at: index)
        // Note: defaultAddressId is intentionally left alone. It may now point at nothing.
    }

    /// PUT /addresses/default (or DELETE /addresses/default when `id` is nil).
    public func setDefault(id: Int?) throws {
        requestLog.append(id.map { "PUT /addresses/default \($0)" } ?? "DELETE /addresses/default")
        if let id, !addresses.contains(where: { $0.id == id }) {
            throw AddressServerError.notFound(id)
        }
        defaultAddressId = id
    }

    /// FNV-1a over the normalised content. Stable across launches (unlike `hashValue`),
    /// never 0, so it cannot collide with the pickup entry.
    static func contentId(for draft: AddressDraft) -> Int {
        let key = [draft.name, draft.street, draft.city]
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .joined(separator: "|")
        var hash: UInt32 = 2_166_136_261
        for byte in key.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % 9_000_000) + 1_000_000
    }
}
