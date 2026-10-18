import SwiftUI

enum AppSettings {
    static let showDistanceKey = "showDistance"
}

struct SettingsView: View {
    @AppStorage(AppSettings.showDistanceKey) private var showDistance = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        form
            .frame(width: 440)
            .fixedSize(horizontal: false, vertical: true)
        #else
        NavigationStack {
            form
                .navigationTitle(L("settings"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button(L("done")) { dismiss() } }
                }
                #endif
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
        #endif
    }

    private var form: some View {
        Form {
            Section {
                Toggle(L("set.distance"), isOn: $showDistance)
                Text(L(showDistance ? "set.distanceOn" : "set.distanceOff"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(L("set.game"))
            }
        }
        .formStyle(.grouped)
    }
}
