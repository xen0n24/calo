import UserNotifications

enum NotificationManager {

    // MARK: - Berechtigung

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static var authorizationStatus: UNAuthorizationStatus {
        get async {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    // MARK: - Tägliche Logging-Erinnerung

    static func scheduleDailyLogging(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["calo.daily-logging"])

        var dc = DateComponents()
        dc.hour   = hour
        dc.minute = minute

        let content      = UNMutableNotificationContent()
        content.title    = "Calo – Zeit zum Tracken"
        content.body     = "Hast du heute schon deine Mahlzeiten eingetragen?"
        content.sound    = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        let request = UNNotificationRequest(
            identifier: "calo.daily-logging",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    static func cancelDailyLogging() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["calo.daily-logging"])
    }

    // MARK: - Wöchentliche Gewichts-Erinnerung

    /// weekday: 1 = Sonntag, 2 = Montag … 7 = Samstag (Apple-Konvention)
    static func scheduleWeighIn(weekday: Int, hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["calo.weigh-in"])

        var dc = DateComponents()
        dc.weekday = weekday
        dc.hour    = hour
        dc.minute  = minute

        let content      = UNMutableNotificationContent()
        content.title    = "Calo – Gewicht eintragen"
        content.body     = "Zeit, dein Gewicht zu messen und einzutragen!"
        content.sound    = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        let request = UNNotificationRequest(
            identifier: "calo.weigh-in",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    static func cancelWeighIn() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["calo.weigh-in"])
    }
}
