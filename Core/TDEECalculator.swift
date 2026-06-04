import Foundation

/// Reine Berechnungsfunktionen – kein Seiteneffekt, gut testbar.
enum TDEECalculator {

    /// Alter in vollen Jahren aus einem Geburtsdatum
    static func age(from birthDate: Date) -> Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
    }

    /// BMR nach Mifflin-St-Jeor
    /// Männer:  10·kg + 6,25·cm − 5·age + 5
    /// Frauen:  10·kg + 6,25·cm − 5·age − 161
    static func bmr(
        sex: Sex,
        weightKg: Double,
        heightCm: Double,
        ageYears: Int
    ) -> Double {
        let base = 10.0 * weightKg + 6.25 * heightCm - 5.0 * Double(ageYears)
        return sex == .male ? base + 5.0 : base - 161.0
    }

    /// TDEE = BMR × Aktivitätsfaktor
    static func tdee(
        sex: Sex,
        weightKg: Double,
        heightCm: Double,
        ageYears: Int,
        activity: ActivityLevel
    ) -> Double {
        bmr(sex: sex, weightKg: weightKg, heightCm: heightCm, ageYears: ageYears) * activity.multiplier
    }

    /// Tägliches Kalorienziel basierend auf TDEE, Ziel und Wunschrate.
    /// - Parameter weeklyRateKg: Betrag in kg/Woche (immer positiv)
    /// - Returns: Ziel-kcal/Tag, mindestens 1 200
    static func calorieTarget(tdee: Double, goal: Goal, weeklyRateKg: Double) -> Int {
        let dailyDelta = abs(weeklyRateKg) * 7_700.0 / 7.0   // 1 kg ≈ 7 700 kcal
        let raw: Double = switch goal {
        case .lose:     tdee - dailyDelta
        case .maintain: tdee
        case .gain:     tdee + dailyDelta
        }
        return max(1_200, Int(raw.rounded()))
    }
}
