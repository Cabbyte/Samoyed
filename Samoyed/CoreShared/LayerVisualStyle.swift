import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum AppTintPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case ocean
    case lagoon
    case meadow
    case amber
    case coral

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .ocean:
            return "Ocean"
        case .lagoon:
            return "Lagoon"
        case .meadow:
            return "Meadow"
        case .amber:
            return "Amber"
        case .coral:
            return "Coral"
        }
    }

    var subtitle: String {
        switch self {
        case .ocean:
            return "Cool blue depth curve."
        case .lagoon:
            return "A crisp teal with calm depth."
        case .meadow:
            return "Fresh green, softer energy."
        case .amber:
            return "Warm gold, brighter emphasis."
        case .coral:
            return "Warm coral with extra punch."
        }
    }

    var tintColor: Color {
        LayerVisualStyle.tintColor(for: self)
    }

    fileprivate var lightHue: CGFloat {
        switch self {
        case .ocean:
            return 218
        case .lagoon:
            return 184
        case .meadow:
            return 145
        case .amber:
            return 36
        case .coral:
            return 10
        }
    }

    fileprivate var darkHue: CGFloat {
        lightHue
    }

    static var current: AppTintPreset {
        SamoyedTintPreference.load()
    }
}

enum SamoyedTintPreference {
    static func load(defaults: UserDefaults = sharedDefaults()) -> AppTintPreset {
        guard
            let rawValue = defaults.string(forKey: SamoyedSharedConfig.tintPresetDefaultsKey),
            let preset = AppTintPreset(rawValue: rawValue)
        else {
            return .ocean
        }

        return preset
    }

    static func save(
        _ preset: AppTintPreset,
        defaults: UserDefaults = sharedDefaults()
    ) {
        defaults.set(preset.rawValue, forKey: SamoyedSharedConfig.tintPresetDefaultsKey)
    }

    private static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: SamoyedSharedConfig.appGroupID) ?? .standard
    }
}

private struct SamoyedTintPresetKey: EnvironmentKey {
    static let defaultValue: AppTintPreset = .ocean
}

extension EnvironmentValues {
    var samoyedTintPreset: AppTintPreset {
        get { self[SamoyedTintPresetKey.self] }
        set { self[SamoyedTintPresetKey.self] = newValue }
    }
}

struct LayerVisualStyle {
    let surface: Color
    let strongSurface: Color
    let border: Color
    let accent: Color
    let marker: Color
    let badgeBackground: Color
    let badgeForeground: Color

    // The solid accent circle needs the opposite contrast from a subtle badge.
    var accentForeground: Color {
        .adaptive(
            light: RGBColor(red: 255, green: 255, blue: 255),
            dark: RGBColor(red: 22, green: 26, blue: 33)
        )
    }

    static func forBlock(
        layerIndex: Int,
        isBlank: Bool,
        preset: AppTintPreset = .current
    ) -> LayerVisualStyle {
        if isBlank {
            return blank
        }

        let depth = max(0, min(layerIndex, paletteRecipes.count - 1))
        return paletteRecipes[depth].style(for: preset)
    }

    static func tintColor(for preset: AppTintPreset) -> Color {
        tintRecipe.color(for: preset)
    }

    private static let tintRecipe = AdaptiveHSVColorRecipe(
        light: HSVColorRecipe(saturation: 0.713, brightness: 0.682),
        dark: HSVColorRecipe(saturation: 0.329, brightness: 1)
    )

    private static let blank = LayerVisualStyle(
        surface: .adaptive(
            light: RGBColor(red: 244, green: 245, blue: 247),
            dark: RGBColor(red: 34, green: 36, blue: 40)
        ),
        strongSurface: .adaptive(
            light: RGBColor(red: 234, green: 237, blue: 241),
            dark: RGBColor(red: 44, green: 47, blue: 52)
        ),
        border: .adaptive(
            light: RGBColor(red: 212, green: 217, blue: 224),
            dark: RGBColor(red: 74, green: 79, blue: 87)
        ),
        accent: .adaptive(
            light: RGBColor(red: 96, green: 103, blue: 114),
            dark: RGBColor(red: 192, green: 197, blue: 206)
        ),
        marker: .adaptive(
            light: RGBColor(red: 142, green: 149, blue: 160),
            dark: RGBColor(red: 124, green: 130, blue: 140)
        ),
        badgeBackground: .adaptive(
            light: RGBColor(red: 226, green: 230, blue: 236),
            dark: RGBColor(red: 58, green: 62, blue: 70)
        ),
        badgeForeground: .adaptive(
            light: RGBColor(red: 90, green: 95, blue: 105),
            dark: RGBColor(red: 220, green: 223, blue: 228)
        )
    )

    // These ramps preserve the current design logic:
    // deeper layers get darker on light backgrounds and lighter on dark backgrounds,
    // while the hue simply swaps with the chosen preset.
    private static let paletteRecipes: [LayerColorRecipe] = [
        LayerColorRecipe(
            surface: .init(
                light: .init(saturation: 0.051, brightness: 1),
                dark: .init(saturation: 0.623, brightness: 0.239)
            ),
            strongSurface: .init(
                light: .init(saturation: 0.098, brightness: 1),
                dark: .init(saturation: 0.605, brightness: 0.298)
            ),
            border: .init(
                light: .init(saturation: 0.253, brightness: 0.961),
                dark: .init(saturation: 0.537, brightness: 0.584)
            ),
            accent: .init(
                light: .init(saturation: 0.713, brightness: 0.682),
                dark: .init(saturation: 0.329, brightness: 1)
            ),
            marker: .init(
                light: .init(saturation: 0.626, brightness: 0.776),
                dark: .init(saturation: 0.45, brightness: 0.941)
            ),
            badgeBackground: .init(
                light: .init(saturation: 0.157, brightness: 1),
                dark: .init(saturation: 0.584, brightness: 0.396)
            ),
            badgeForeground: .init(
                light: .init(saturation: 0.788, brightness: 0.518),
                dark: .init(saturation: 0.098, brightness: 1)
            )
        ),
        LayerColorRecipe(
            surface: .init(
                light: .init(saturation: 0.106, brightness: 1),
                dark: .init(saturation: 0.623, brightness: 0.208)
            ),
            strongSurface: .init(
                light: .init(saturation: 0.175, brightness: 0.984),
                dark: .init(saturation: 0.612, brightness: 0.263)
            ),
            border: .init(
                light: .init(saturation: 0.396, brightness: 0.941),
                dark: .init(saturation: 0.58, brightness: 0.541)
            ),
            accent: .init(
                light: .init(saturation: 0.821, brightness: 0.612),
                dark: .init(saturation: 0.294, brightness: 1)
            ),
            marker: .init(
                light: .init(saturation: 0.726, brightness: 0.702),
                dark: .init(saturation: 0.412, brightness: 0.953)
            ),
            badgeBackground: .init(
                light: .init(saturation: 0.243, brightness: 0.984),
                dark: .init(saturation: 0.596, brightness: 0.349)
            ),
            badgeForeground: .init(
                light: .init(saturation: 0.847, brightness: 0.463),
                dark: .init(saturation: 0.082, brightness: 1)
            )
        ),
        LayerColorRecipe(
            surface: .init(
                light: .init(saturation: 0.151, brightness: 0.988),
                dark: .init(saturation: 0.63, brightness: 0.18)
            ),
            strongSurface: .init(
                light: .init(saturation: 0.252, brightness: 0.965),
                dark: .init(saturation: 0.621, brightness: 0.227)
            ),
            border: .init(
                light: .init(saturation: 0.513, brightness: 0.91),
                dark: .init(saturation: 0.605, brightness: 0.486)
            ),
            accent: .init(
                light: .init(saturation: 0.882, brightness: 0.533),
                dark: .init(saturation: 0.263, brightness: 1)
            ),
            marker: .init(
                light: .init(saturation: 0.792, brightness: 0.624),
                dark: .init(saturation: 0.377, brightness: 0.969)
            ),
            badgeBackground: .init(
                light: .init(saturation: 0.329, brightness: 0.965),
                dark: .init(saturation: 0.612, brightness: 0.314)
            ),
            badgeForeground: .init(
                light: .init(saturation: 0.88, brightness: 0.392),
                dark: .init(saturation: 0.075, brightness: 1)
            )
        ),
        LayerColorRecipe(
            surface: .init(
                light: .init(saturation: 0.202, brightness: 0.973),
                dark: .init(saturation: 0.625, brightness: 0.157)
            ),
            strongSurface: .init(
                light: .init(saturation: 0.339, brightness: 0.937),
                dark: .init(saturation: 0.608, brightness: 0.2)
            ),
            border: .init(
                light: .init(saturation: 0.624, brightness: 0.867),
                dark: .init(saturation: 0.609, brightness: 0.431)
            ),
            accent: .init(
                light: .init(saturation: 0.93, brightness: 0.447),
                dark: .init(saturation: 0.231, brightness: 1)
            ),
            marker: .init(
                light: .init(saturation: 0.855, brightness: 0.541),
                dark: .init(saturation: 0.333, brightness: 0.976)
            ),
            badgeBackground: .init(
                light: .init(saturation: 0.424, brightness: 0.933),
                dark: .init(saturation: 0.623, brightness: 0.271)
            ),
            badgeForeground: .init(
                light: .init(saturation: 0.916, brightness: 0.325),
                dark: .init(saturation: 0.063, brightness: 1)
            )
        )
    ]
}

private struct LayerColorRecipe {
    let surface: AdaptiveHSVColorRecipe
    let strongSurface: AdaptiveHSVColorRecipe
    let border: AdaptiveHSVColorRecipe
    let accent: AdaptiveHSVColorRecipe
    let marker: AdaptiveHSVColorRecipe
    let badgeBackground: AdaptiveHSVColorRecipe
    let badgeForeground: AdaptiveHSVColorRecipe

    func style(for preset: AppTintPreset) -> LayerVisualStyle {
        LayerVisualStyle(
            surface: surface.color(for: preset),
            strongSurface: strongSurface.color(for: preset),
            border: border.color(for: preset),
            accent: accent.color(for: preset),
            marker: marker.color(for: preset),
            badgeBackground: badgeBackground.color(for: preset),
            badgeForeground: badgeForeground.color(for: preset)
        )
    }
}

private struct AdaptiveHSVColorRecipe {
    let light: HSVColorRecipe
    let dark: HSVColorRecipe

    func color(for preset: AppTintPreset) -> Color {
        .adaptive(
            light: light.rgbColor(hue: preset.lightHue),
            dark: dark.rgbColor(hue: preset.darkHue)
        )
    }
}

private struct HSVColorRecipe {
    let hueOffset: CGFloat
    let saturation: CGFloat
    let brightness: CGFloat

    init(
        hueOffset: CGFloat = 0,
        saturation: CGFloat,
        brightness: CGFloat
    ) {
        self.hueOffset = hueOffset
        self.saturation = saturation
        self.brightness = brightness
    }

    func rgbColor(hue: CGFloat) -> RGBColor {
        RGBColor(
            hue: hue + hueOffset,
            saturation: saturation,
            brightness: brightness
        )
    }
}

private struct RGBColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        let normalizedHue = ((hue.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360) / 60
        let chroma = brightness * saturation
        let intermediate = chroma * (1 - abs(normalizedHue.truncatingRemainder(dividingBy: 2) - 1))
        let match = brightness - chroma

        let components: (CGFloat, CGFloat, CGFloat)
        switch normalizedHue {
        case 0 ..< 1:
            components = (chroma, intermediate, 0)
        case 1 ..< 2:
            components = (intermediate, chroma, 0)
        case 2 ..< 3:
            components = (0, chroma, intermediate)
        case 3 ..< 4:
            components = (0, intermediate, chroma)
        case 4 ..< 5:
            components = (intermediate, 0, chroma)
        default:
            components = (chroma, 0, intermediate)
        }

        red = ((components.0 + match) * 255).rounded()
        green = ((components.1 + match) * 255).rounded()
        blue = ((components.2 + match) * 255).rounded()
    }
}

private extension Color {
    static func adaptive(light: RGBColor, dark: RGBColor, alpha: CGFloat = 1) -> Color {
        #if canImport(UIKit)
        return Color(
            uiColor: UIColor { traits in
                let palette = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: palette.red / 255,
                    green: palette.green / 255,
                    blue: palette.blue / 255,
                    alpha: alpha
                )
            }
        )
        #elseif canImport(AppKit)
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                let palette = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                return NSColor(
                    deviceRed: palette.red / 255,
                    green: palette.green / 255,
                    blue: palette.blue / 255,
                    alpha: alpha
                )
            }
        )
        #else
        return Color(
            .sRGB,
            red: light.red / 255,
            green: light.green / 255,
            blue: light.blue / 255,
            opacity: alpha
        )
        #endif
    }
}
