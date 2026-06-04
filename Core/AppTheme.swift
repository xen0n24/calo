import SwiftUI
import Observation

// MARK: - Color Extensions

extension Color {
    /// Initialisierung aus einem Hex-String wie "#34C759" oder "34C759"
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int & 0xFF0000) >> 16) / 255.0
        let g = Double((int & 0x00FF00) >> 8)  / 255.0
        let b = Double(int  & 0x0000FF)         / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// Gibt den Hex-String dieser Farbe zurück (ohne Transparenz)
    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((r * 255.0).rounded()),
                      Int((g * 255.0).rounded()),
                      Int((b * 255.0).rounded()))
    }
}

// MARK: - AppTheme

@Observable @MainActor final class AppTheme {

    // MARK: Farb-Slots (als Hex-Strings in UserDefaults)

    var accentLightHex: String = UserDefaults.standard.string(forKey: "theme.accent.light") ?? "#34C759" {
        didSet { UserDefaults.standard.set(accentLightHex, forKey: "theme.accent.light") }
    }

    var accentDarkHex: String = UserDefaults.standard.string(forKey: "theme.accent.dark") ?? "#34C759" {
        didSet { UserDefaults.standard.set(accentDarkHex, forKey: "theme.accent.dark") }
    }

    var proteinHex: String = UserDefaults.standard.string(forKey: "theme.macro.protein") ?? "#007AFF" {
        didSet { UserDefaults.standard.set(proteinHex, forKey: "theme.macro.protein") }
    }

    var carbsHex: String = UserDefaults.standard.string(forKey: "theme.macro.carbs") ?? "#FF9F0A" {
        didSet { UserDefaults.standard.set(carbsHex, forKey: "theme.macro.carbs") }
    }

    var fatHex: String = UserDefaults.standard.string(forKey: "theme.macro.fat") ?? "#FFCC00" {
        didSet { UserDefaults.standard.set(fatHex, forKey: "theme.macro.fat") }
    }

    var waterHex: String = UserDefaults.standard.string(forKey: "theme.water") ?? "#5AC8FA" {
        didSet { UserDefaults.standard.set(waterHex, forKey: "theme.water") }
    }

    var warningHex: String = UserDefaults.standard.string(forKey: "theme.warning") ?? "#FF375F" {
        didSet { UserDefaults.standard.set(warningHex, forKey: "theme.warning") }
    }

    var bodyMeasurementHex: String = UserDefaults.standard.string(forKey: "theme.bodyMeasurement") ?? "#9747FF" {
        didSet { UserDefaults.standard.set(bodyMeasurementHex, forKey: "theme.bodyMeasurement") }
    }

    var sameForBothModes: Bool = (UserDefaults.standard.object(forKey: "theme.sameForBothModes") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(sameForBothModes, forKey: "theme.sameForBothModes") }
    }

    // MARK: Berechnete Color-Properties

    /// Akzentfarbe passend zum ColorScheme (relevant wenn sameForBothModes == false)
    func accentColor(for scheme: ColorScheme) -> Color {
        if sameForBothModes { return Color(hex: accentLightHex) }
        return scheme == .dark ? Color(hex: accentDarkHex) : Color(hex: accentLightHex)
    }

    /// Convenience: Light-Variante (ausreichend wenn sameForBothModes == true)
    var accent:          Color { Color(hex: accentLightHex) }
    var protein:         Color { Color(hex: proteinHex) }
    var carbs:           Color { Color(hex: carbsHex) }
    var fat:             Color { Color(hex: fatHex) }
    var water:           Color { Color(hex: waterHex) }
    var warning:         Color { Color(hex: warningHex) }
    var bodyMeasurement: Color { Color(hex: bodyMeasurementHex) }

    // MARK: Reset

    func resetToDefaults() {
        accentLightHex   = "#34C759"
        accentDarkHex    = "#34C759"
        proteinHex       = "#007AFF"
        carbsHex         = "#FF9F0A"
        fatHex           = "#FFCC00"
        waterHex         = "#5AC8FA"
        warningHex          = "#FF375F"
        bodyMeasurementHex  = "#9747FF"
        sameForBothModes    = true
    }
}
