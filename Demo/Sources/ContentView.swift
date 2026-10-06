import SwiftUI
import StaleDefaultReference

struct ContentView: View {
    @State private var model = DemoModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Client", selection: $model.mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("modePicker")
                    Text(explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Saved addresses (what the UI shows)") {
                    ForEach(model.rows, id: \.address.id) { row in
                        AddressRowView(row: row)
                            .swipeActions {
                                if !row.address.isSynthetic {
                                    Button("Delete", role: .destructive) { model.delete(row.address) }
                                }
                            }
                    }
                }

                Section("Server state (what is actually stored)") {
                    LabeledContent("Default id", value: model.name(for: model.serverDefaultId))
                        .foregroundStyle(model.defaultIsDangling ? .red : .primary)
                    if model.defaultIsDangling {
                        Text("Dangling reference: the UI badges another row, but the server still holds the deleted id.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Re-add Home") { model.reAddHome() }
                        .disabled(model.homeIsListed)
                    Button("Reset", role: .destructive) { model.reset() }
                }

                Section("Log") {
                    ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("Stale default")
            .task { await model.autorunIfRequested() }
            .confirmationDialog(
                "Make this your default?",
                isPresented: Binding(get: { model.pendingPrompt != nil },
                                     set: { if !$0 { model.answer(makeDefault: false) } }),
                titleVisibility: .visible
            ) {
                Button("Make default") { model.answer(makeDefault: true) }
                Button("Not now", role: .cancel) { model.answer(makeDefault: false) }
            }
        }
    }

    private var explanation: String {
        let steps = "Swipe to delete Home (the default), tap Re-add Home, answer \"Not now\"."
        switch model.mode {
        case .naive:
            return steps + " Naive: after the delete the list badges Office, but the server default still points at the deleted id. The re-added Home gets the same id, so it comes back as Default even though you said Not now."
        case .fixed:
            return steps + " Fixed: the delete also moves the server default to Office, so the re-added Home stays a normal address."
        }
    }
}

private struct AddressRowView: View {
    let row: AddressRow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.address.name).font(.body)
                Text(row.address.isSynthetic ? "id 0 · system entry" : "id \(row.address.id) · \(row.address.street), \(row.address.city)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if row.showsDefaultBadge {
                Text("Default")
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.blue.opacity(0.15), in: Capsule())
                    .foregroundStyle(.blue)
            }
        }
    }
}
