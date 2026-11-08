#if os(iOS) || os(macOS)
import Foundation
import UserNotifications

/// Günlük hatırlatma (iPhone ve Mac). Bildirim yalnızca o gün hiçbir kategoride günlük bulmaca
/// bitirilmediyse gelsin diye tekrarlayan bir bildirim yerine önümüzdeki 7 günün her biri ayrı kurulur;
/// uygulama her açıldığında ve günlük bulmaca bitince yeniden kurulur (bugün oynandıysa bugünkü atlanır).
enum Reminders {
    static let enabledKey = "reminder.enabled"
    static let hourKey = "reminder.hour"
    static let minuteKey = "reminder.minute"
    private static let days = 7

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Seçili saat (varsayılan 19:00).
    static var time: DateComponents {
        let d = UserDefaults.standard
        return DateComponents(hour: d.object(forKey: hourKey) as? Int ?? 19, minute: d.object(forKey: minuteKey) as? Int ?? 0)
    }

    /// İzin ister; verilmezse false.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// Bekleyen hatırlatmaları siler ve (açıksa) önümüzdeki günler için yeniden kurar.
    static func refresh() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (0..<days).map { "atlas.reminder.\($0)" })
        guard isEnabled else { return }
        let cal = Calendar.current
        let now = Date.now
        let today = DailyPuzzle.dayIndex(for: now)
        let playedToday = GameCategory.allCases.contains { c in
            guard let saved = GameModel.savedDaily(category: c, day: today) else { return false }
            return saved.status != .playing
        }
        let streak = currentStreak(today: today)
        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            var parts = cal.dateComponents([.year, .month, .day], from: day)
            parts.hour = time.hour
            parts.minute = time.minute
            guard let fire = cal.date(from: parts), fire > now else { continue }
            if offset == 0 && playedToday { continue }

            let content = UNMutableNotificationContent()
            // Seri yalnızca bugün için kesin; sonraki günlerde bozulmuş olabilir.
            if offset == 0 && streak > 0 {
                content.title = L("reminder.streakTitle")
                content.body = L("reminder.streakBody", ["n": streak])
            } else {
                content.title = "Atlas"
                content.body = L("reminder.body")
            }
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: "atlas.reminder.\(offset)", content: content, trigger: trigger))
        }
    }

    /// Kategoriler arasında en uzun süren günlük seri.
    private static func currentStreak(today: Int) -> Int {
        GameCategory.allCases.map { c in
            var s = Stats.load(key: Stats.key(category: c, mode: .daily))
            s.refreshStreak(today: today)
            return s.currentStreak
        }.max() ?? 0
    }
}
#endif
