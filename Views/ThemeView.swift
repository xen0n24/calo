import SwiftUI

// MARK: - ThemePreviewCard

/// Zeigt eine Mini-Vorschau der aktuellen Theme-Farben.
/// Aktualisiert sich automatisch wenn AppTheme sich ändert.
struct ThemePreviewCard: View {
    @Environment(AppTheme.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { theme.accentColor(for: colorScheme) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                // Kalorien-Ring
                ZStack {
                    Circle()
                        .stroke(accent.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(accent,
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("1850")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                        Text("kcal")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)

                // Makro- und Wasserbalken
                VStack(spacing: 6) {
                    previewBar(color: theme.protein, fraction: 0.70, label: "Protein")
                    previewBar(color: theme.carbs,   fraction: 0.55, label: "Kohlenhydr.")
                    previewBar(color: theme.fat,     fraction: 0.40, label: "Fett")
                    previewBar(color: theme.water,   fraction: 0.60, label: "Wasser")
                }
            }

            // Button-Vorschau
            HStack {
                Label("Eintrag hinzufügen", systemImage: "plus.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer()
                Text("2100 kcal Ziel")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func previewBar(color: Color, fraction: Double, label: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.15))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.75))
                        .frame(width: geo.size.width * fraction, height: 5)
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - NormalThemeSection

struct NormalThemeSection: View {
    @Environment(AppTheme.self) private var theme

    private let presets = [
        "#34C759", "#007AFF", "#FF9F0A", "#FF375F",
        "#BF5AF2", "#5AC8FA", "#FF6B35"
    ]

    var body: some View {
        @Bindable var theme = theme

        VStack(alignment: .leading, spacing: 16) {

            // Farbwahl
            VStack(alignment: .leading, spacing: 10) {
                Text("Akzentfarbe")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 10) {
                    ForEach(presets, id: \.self) { hex in
                        swatchButton(hex: hex)
                    }
                    // Freier Farbwähler
                    ColorPicker("Eigene Farbe",
                                selection: customBinding,
                                supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 36, height: 36)
                }
            }

            // Dark/Light Toggle
            Toggle("Gleich für Dark & Light Mode", isOn: $theme.sameForBothModes)
                .onChange(of: theme.sameForBothModes) { _, same in
                    if same { theme.accentDarkHex = theme.accentLightHex }
                }

            // Wenn getrennte Modi aktiv: zwei separate Picker
            if !theme.sameForBothModes {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hell-Modus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ColorPicker("Hell",
                                    selection: hexBinding(\.accentLightHex),
                                    supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 36, height: 36)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dunkel-Modus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ColorPicker("Dunkel",
                                    selection: hexBinding(\.accentDarkHex),
                                    supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 36, height: 36)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: Hilfsmethoden

    @ViewBuilder
    private func swatchButton(hex: String) -> some View {
        let isSelected = theme.accentLightHex == hex
        Button { selectAccent(hex) } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white, lineWidth: isSelected ? 3 : 0)
                )
                .shadow(color: isSelected ? Color(hex: hex).opacity(0.6) : .clear,
                        radius: 4)
        }
        .buttonStyle(.plain)
    }

    private func selectAccent(_ hex: String) {
        theme.accentLightHex = hex
        if theme.sameForBothModes { theme.accentDarkHex = hex }
    }

    private func hexBinding(_ keyPath: ReferenceWritableKeyPath<AppTheme, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: theme[keyPath: keyPath]) },
            set: { theme[keyPath: keyPath] = $0.toHex() }
        )
    }

    private var customBinding: Binding<Color> {
        Binding(
            get: { Color(hex: theme.accentLightHex) },
            set: { newColor in
                let hex = newColor.toHex()
                theme.accentLightHex = hex
                if theme.sameForBothModes { theme.accentDarkHex = hex }
            }
        )
    }
}

// MARK: - AdvancedThemeSection

struct AdvancedThemeSection: View {
    @Environment(AppTheme.self) private var theme

    var body: some View {
        @Bindable var theme = theme

        VStack(spacing: 0) {

            // Hauptfarbe
            sectionHeader("Hauptfarbe")
            colorRow(label: "Akzent (Ring, Buttons, Kalorienzahl)",
                     keyPath: \.accentLightHex)

            Toggle("Gleich für Dark & Light Mode", isOn: $theme.sameForBothModes)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .onChange(of: theme.sameForBothModes) { _, same in
                    if same { theme.accentDarkHex = theme.accentLightHex }
                }

            if !theme.sameForBothModes {
                colorRow(label: "Akzent – Dunkel-Modus", keyPath: \.accentDarkHex)
            }

            Divider().padding(.vertical, 8)

            // Makro-Balken
            sectionHeader("Makro-Balken")
            colorRow(label: "Protein",       keyPath: \.proteinHex)
            colorRow(label: "Kohlenhydrate", keyPath: \.carbsHex)
            colorRow(label: "Fett",          keyPath: \.fatHex)

            Divider().padding(.vertical, 8)

            // Weitere Farben
            sectionHeader("Weitere Farben")
            colorRow(label: "Wasser",              keyPath: \.waterHex)
            colorRow(label: "Warnung / Überschuss", keyPath: \.warningHex)
            colorRow(label: "Körpermaße",           keyPath: \.bodyMeasurementHex)
        }
    }

    // MARK: Hilfsmethoden

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
    }

    private func colorRow(label: String,
                          keyPath: ReferenceWritableKeyPath<AppTheme, String>) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            ColorPicker("",
                        selection: hexBinding(keyPath),
                        supportsOpacity: false)
                .labelsHidden()
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func hexBinding(_ keyPath: ReferenceWritableKeyPath<AppTheme, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: theme[keyPath: keyPath]) },
            set: { theme[keyPath: keyPath] = $0.toHex() }
        )
    }
}

// MARK: - ThemeView

struct ThemeView: View {
    @Environment(AppTheme.self) private var theme

    @State private var mode: ThemeMode = .normal
    @State private var showResetConfirmation = false

    enum ThemeMode: String, CaseIterable {
        case normal    = "Normal"
        case advanced  = "Fortgeschritten"
    }

    var body: some View {
        List {
            // Modus-Auswahl
            Section {
                Picker("Modus", selection: $mode) {
                    ForEach(ThemeMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Farbeinstellungen
            Section {
                if mode == .normal {
                    NormalThemeSection()
                        .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
                } else {
                    AdvancedThemeSection()
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }

            // Live-Vorschau
            Section("Vorschau") {
                ThemePreviewCard()
                    .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            // Reset
            Section {
                Button("Alle Farben zurücksetzen", role: .destructive) {
                    showResetConfirmation = true
                }
            } footer: {
                Text("Setzt alle Farben auf die Standardwerte zurück.")
            }
        }
        .navigationTitle("Design anpassen")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Standardfarben wiederherstellen?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Zurücksetzen", role: .destructive) {
                theme.resetToDefaults()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle eigenen Farbeinstellungen werden gelöscht.")
        }
    }
}
