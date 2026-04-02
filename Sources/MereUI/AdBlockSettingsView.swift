import SwiftUI
import MereCore

public struct AdBlockSettingsView: View {

    @ObservedObject var adBlock: AdBlockController

    public init(adBlock: AdBlockController) {
        self.adBlock = adBlock
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Master toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ad & Tracker Blocking")
                        .font(.headline)
                    Text("\(adBlock.totalRuleCount.formatted()) rules · \(adBlock.totalBlockedCount.formatted()) blocked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { adBlock.isEnabled },
                    set: { adBlock.setEnabled($0) }
                ))
                .labelsHidden()
            }

            Divider()

            // Loaded lists
            if adBlock.loadedLists.isEmpty {
                Text("No lists loaded")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(Array(adBlock.loadedLists.keys.sorted()), id: \.self) { name in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.subheadline)
                            if let count = adBlock.loadedLists[name] {
                                Text("\(count.formatted()) rules")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            Task { await adBlock.remove(listNamed: name) }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Load default lists
            HStack {
                Button("Load EasyList + EasyPrivacy") {
                    Task { await adBlock.loadDefaults() }
                }
                .disabled(adBlock.isLoading)

                if adBlock.isLoading {
                    ProgressView().scaleEffect(0.7)
                }
            }

            if let error = adBlock.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
