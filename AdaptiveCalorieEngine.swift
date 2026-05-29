import Foundation

// MARK: - Ergebnis-Typen

struct AdaptiveResult {
    /// Empfohlene Änderung am Tagesziel (negativ = weniger essen, positiv = mehr essen)
    let adjustmentKcal: Int
    /// Tatsächliche Gewichtsveränderung der letzten 7 Tage (kg/Woche)
    let actualRatePerWeek: Double
    /// Zielrate laut Profil (negativ = abnehmen, 0 = halten, positiv = zunehmen)
    let targetRatePerWeek: Double
    /// Berechnetes neues Kalorienziel
    let newTarget: Int
}

enum AdaptiveStatus {
    /// Zu wenig Gewichtseinträge im 14-Tage-Fenster
    case insufficientData(have: Int, need: Int)
    /// Gut auf Kurs, keine Anpassung nötig
    case onTrack(actualRatePerWeek: Double)
    /// Empfehlung vorhanden
    case recommendation(AdaptiveResult)
}

// MARK: - Engine (pure functions)

enum AdaptiveCalorieEngine {

    // Mindestanzahl Gewichtseinträge pro 14-Tage-Fenster
    static let minEntries = 4

    /// Wertet die letzten 14 Tage aus und gibt einen Status zurück.
    static func evaluate(
        weightEntries: [WeightEntry],
        profile: UserProfile
    ) -> AdaptiveStatus {
        let now         = Date()
        let cal         = Calendar.current
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: now)!
        let oneWeekAgo  = cal.date(byAdding: .day, value:  -7, to: now)!

        // Nur Einträge im 14-Tage-Fenster
        let window = weightEntries.filter { $0.date >= twoWeeksAgo }
        guard window.count >= minEntries else {
            return .insufficientData(have: window.count, need: minEntries)
        }

        // 7-Tage-Mittel: aktuelle Woche vs. vorherige Woche
        let currentWeek  = window.filter { $0.date >= oneWeekAgo }
        let previousWeek = window.filter { $0.date < oneWeekAgo }
        guard !currentWeek.isEmpty, !previousWeek.isEmpty else {
            return .insufficientData(have: window.count, need: minEntries)
        }

        let avgCurrent  = currentWeek.map(\.weightKg).reduce(0, +)  / Double(currentWeek.count)
        let avgPrevious = previousWeek.map(\.weightKg).reduce(0, +) / Double(previousWeek.count)

        // Tatsächliche Rate in kg/Woche (positiv = zugenommen)
        let actualRate = avgCurrent - avgPrevious

        // Zielrate laut Profil
        let targetRate: Double = switch profile.goal {
        case .lose:     -abs(profile.weeklyRateKg)
        case .maintain:  0.0
        case .gain:      abs(profile.weeklyRateKg)
        }

        // Abweichung und Anpassung
        // deviation > 0 → zu viel zugenommen → weniger essen (negatives adjustmentKcal)
        let deviation       = actualRate - targetRate
        let rawKcal         = (deviation / 0.1) * 100.0
        let clampedKcal     = max(-400, min(400, Int(rawKcal.rounded())))
        let adjustmentKcal  = -clampedKcal      // Vorzeichen umdrehen: neg. = weniger essen

        // Schwelle: Anpassungen unter ±50 kcal ignorieren
        if abs(adjustmentKcal) < 50 {
            return .onTrack(actualRatePerWeek: actualRate)
        }

        // Minimum: BMR × 1,1
        let age        = TDEECalculator.age(from: profile.birthDate)
        let bmrValue   = TDEECalculator.bmr(
            sex: profile.sex, weightKg: avgCurrent,
            heightCm: profile.heightCm, ageYears: age
        )
        let minTarget  = Int((bmrValue * 1.1).rounded())
        let newTarget  = max(minTarget, profile.currentCalorieTarget + adjustmentKcal)

        return .recommendation(AdaptiveResult(
            adjustmentKcal:    adjustmentKcal,
            actualRatePerWeek: actualRate,
            targetRatePerWeek: targetRate,
            newTarget:         newTarget
        ))
    }
}
