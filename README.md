# Stale default after delete + id reuse

A minimal Swift reproduction of an API-contract trap:

1. The server stores the user's **default address id** separately from the list of saved addresses.
2. `DELETE /addresses/{id}` removes the address but **does not clear the default**.
3. The server derives ids **from the content**, so re-adding the same address returns **the same id**.

Delete the default address, re-add it, answer **"Not now"** to "Make this your default?" — and it shows up as the default anyway, because the stale default id matches again.

Meanwhile the list screen looked fine the whole time: it badged the first remaining address as "Default" via a display fallback, hiding the dangling reference.

## How to run

**In Xcode (demo app + tests):**

1. Open `Demo/Demo.xcodeproj` (Xcode 16+; it references this package locally).
2. Pick an iPhone simulator (iOS 17+) and press **⌘R**.
3. Use the **Naive / Fixed** switch at the top, then: swipe to delete **Home** (the default), tap **Re-add Home**, answer **"Not now"**.
   - **Naive:** after the delete the list badges Office, but the *Server state* section shows the default id in red, pointing at nothing. After re-adding, Home comes back with the **Default** badge even though you said "Not now".
   - **Fixed:** the delete also moves the server default to Office, so the re-added Home stays a normal address.
4. Press **⌘U** to run the package's test suite (the `Demo` scheme includes `StaleDefaultReferenceTests`). Tests asserting the Naive bug *pass* — they document that the bug exists.

**From the command line:** the library is plain Swift (no UIKit), so `swift test` works on macOS too.

## What's inside

- `Sources/StaleDefaultReference/FakeAddressServer.swift` — in-memory backend with the contract above (content-derived ids, default not cleared on delete, a synthetic "Pick up in store" entry with id 0).
- `Sources/StaleDefaultReference/AddressBook.swift`
  - `NaiveAddressBook` — deletes only the address; badges the first address when the default matches nothing.
  - `FixedAddressBook` — captures "was this the default?" before deleting, then after a successful delete sets the next real address as default (or clears it); never promotes the id-0 entry; badges only from server state.
- `Tests/StaleDefaultReferenceTests` — Swift Testing suites:
  - **Backend contract** — re-adding returns the same id; delete leaves the default dangling.
  - **Naive client** — the fallback hides the dangling default; the re-added address becomes default despite "Not now".
  - **Fixed client** — "Not now" is respected; the next real address is promoted; id 0 is never promoted; deleting the last address clears the default; deleting a non-default or a failed delete changes nothing.

## The fix in one place

```swift
public func delete(id: Int) throws {
    let wasDefault = server.defaultAddressId == id          // capture BEFORE the delete
    try server.delete(id: id)                               // DELETE /addresses/{id}
    guard wasDefault else { return }
    let successor = server.list().first { !$0.isSynthetic && $0.id != id }
    try server.setDefault(id: successor?.id)                // PUT, or DELETE when nil
}
```

## Run

```bash
swift test
```

Requires Xcode 16+ / Swift 6 (Swift Testing). No simulator needed.

## License

MIT

Write-up: https://alexeyhatkevich.blogspot.com
