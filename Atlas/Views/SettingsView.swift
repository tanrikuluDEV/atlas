import SwiftUI

enum AppSettings {
    static let showDistanceKey = "showDistance"
    static let expertKey = "expert"
}

/// Oyunu etkileyen ayarlar; `GameModel` gözlemleyebilsin diye @Observable (UserDefaults'ta saklanır).
@Observable
final class GameSettings {
    static let shared = GameSettings()

    /// Uzman modu: haritada adlar ve mesafeler gizlenir, yalnızca renk kalır; kazanılan puan %30 fazla.
    var expert: Bool = UserDefaults.standard.bool(forKey: AppSettings.expertKey) {
        didSet { UserDefaults.standard.set(expert, forKey: AppSettings.expertKey) }
    }
}

struct SettingsView: View {
    @AppStorage(AppSettings.showDistanceKey) private var showDistance = true
    @AppStorage(GameFeedback.soundKey) private var sound = false
    @AppStorage(GameFeedback.hapticsKey) private var haptics = true
    @State private var settings = GameSettings.shared
    #if os(iOS) || os(macOS)
    @AppStorage(Reminders.enabledKey) private var reminder = false
    @AppStorage(Reminders.hourKey) private var reminderHour = 19
    @AppStorage(Reminders.minuteKey) private var reminderMinute = 0
    @State private var reminderDenied = false
    #endif

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
        .presentationDetents([.medium, .large])
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
                Toggle(L("set.expert"), isOn: $settings.expert)
                Text(L("set.expertHint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(L("set.game"))
            }
            Section {
                Toggle(L("set.sound"), isOn: $sound)
                Text(L("set.soundHint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                #if os(iOS)
                Toggle(L("set.haptics"), isOn: $haptics)
                Text(L("set.hapticsHint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                #endif
            }
            #if os(iOS) || os(macOS)
            reminderSection
            #endif
        }
        .formStyle(.grouped)
    }

    #if os(iOS) || os(macOS)
    private var reminderSection: some View {
        Section {
            Toggle(L("set.reminder"), isOn: Binding(get: { reminder }, set: { on in
                guard on else { reminder = false; Reminders.refresh(); return }
                Task { @MainActor in
                    let granted = await Reminders.requestPermission()
                    reminderDenied = !granted
                    reminder = granted
                    Reminders.refresh()
                }
            }))
            if reminder {
                DatePicker(L("set.reminderTime"), selection: Binding(get: {
                    Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? .now
                }, set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    reminderHour = parts.hour ?? 19
                    reminderMinute = parts.minute ?? 0
                    Reminders.refresh()
                }), displayedComponents: .hourAndMinute)
            }
            Text(L(reminderDenied ? "set.reminderDenied" : "set.reminderHint"))
                .font(.callout)
                .foregroundStyle(reminderDenied ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif
}
