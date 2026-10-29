import SwiftUI

/// The look the app is shown in. Each person picks one on their own phone (Family tab → Theme);
/// it only changes colors, animals and backgrounds, never how anything works.
enum AppTheme: String, CaseIterable, Identifiable {
    case jungle, ocean, space, dinosaur, princess

    static let storageKey = "appTheme"

    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .jungle
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .jungle: return "Jungle"
        case .ocean: return "Ocean"
        case .space: return "Space"
        case .dinosaur: return "Dinosaur"
        case .princess: return "Princess"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .jungle: return .jungle
        case .ocean: return .ocean
        case .space: return .space
        case .dinosaur: return .dinosaur
        case .princess: return .princess
        }
    }

    var art: ThemeArt {
        switch self {
        case .jungle: return .jungle
        case .ocean: return .ocean
        case .space: return .space
        case .dinosaur: return .dinosaur
        case .princess: return .princess
        }
    }
}

/// A light and a dark (night mode) version of one color.
struct ThemeColor {
    let light: UInt32
    let dark: UInt32

    init(_ light: UInt32, _ dark: UInt32) {
        self.light = light
        self.dark = dark
    }
}

/// The colors of a theme. Names come from the original jungle theme; in other themes
/// they're simply the main color, the second green-ish color, the sunshine yellow and so on.
struct ThemePalette {
    let canopy: ThemeColor   // main tint: titles, buttons
    let leaf: ThemeColor     // secondary color, tummy time
    let lime: ThemeColor     // soft accent behind badges
    let sunshine: ThemeColor // milestones
    let mango: ThemeColor    // bottles
    let hibiscus: ThemeColor // feeds
    let orchid: ThemeColor   // pumping, vaccines
    let lagoon: ThemeColor   // diapers
    let river: ThemeColor    // growth, appointments
    let dusk: ThemeColor     // sleep
    let bark: ThemeColor     // dirty diapers, small print
    let backgroundTop: ThemeColor
    let backgroundBottom: ThemeColor
    /// Card surface at night (by day cards are soft white).
    let nightCard: UInt32

    static let jungle = ThemePalette(
        canopy: .init(0x2E6B4A, 0x7FD49B), leaf: .init(0x5DB563, 0x6CC774), lime: .init(0xB8E07E, 0x5E8A3E),
        sunshine: .init(0xF7B731, 0xF9C74F), mango: .init(0xF28C38, 0xF6A05A), hibiscus: .init(0xE8566C, 0xF0798B),
        orchid: .init(0x9B6BD3, 0xB592E6), lagoon: .init(0x23A6A6, 0x4CC9C4), river: .init(0x3F7FD0, 0x6FA2E8),
        dusk: .init(0x5B5FC7, 0x9A9DF0), bark: .init(0x6B4A2E, 0xD9B98F),
        backgroundTop: .init(0xFFF7E6, 0x0F1F17), backgroundBottom: .init(0xEAF6DF, 0x132A1E), nightCard: 0x1F3829
    )

    static let ocean = ThemePalette(
        canopy: .init(0x175E86, 0x7CCBF0), leaf: .init(0x2FB59A, 0x52CDB2), lime: .init(0xA6E3E9, 0x2C6F7E),
        sunshine: .init(0xF5C33B, 0xF8D06A), mango: .init(0xF48C5B, 0xF7A57E), hibiscus: .init(0xEF6A6A, 0xF48C8C),
        orchid: .init(0x8C7AD6, 0xAE9FEA), lagoon: .init(0x1AA7C2, 0x4CC6DD), river: .init(0x2F72D6, 0x6C9DEB),
        dusk: .init(0x3E54C1, 0x8E9DF0), bark: .init(0x7A6448, 0xD9C3A0),
        backgroundTop: .init(0xEAF8FC, 0x081A2A), backgroundBottom: .init(0xCFEFF5, 0x0B2A3E), nightCard: 0x14324A
    )

    static let space = ThemePalette(
        canopy: .init(0x4A3DA8, 0xB9AEFF), leaf: .init(0x38B58A, 0x5CD1A6), lime: .init(0xD3CCF7, 0x3D3680),
        sunshine: .init(0xF2B632, 0xF8CC5E), mango: .init(0xF2864A, 0xF6A472), hibiscus: .init(0xE8559A, 0xF07DB3),
        orchid: .init(0x9A62DE, 0xBB92EE), lagoon: .init(0x22A9C4, 0x52C8DE), river: .init(0x4473E6, 0x7C9FF2),
        dusk: .init(0x5446CF, 0x9C92F2), bark: .init(0x5B5876, 0xC5C2DD),
        backgroundTop: .init(0xF2EFFC, 0x0B0B22), backgroundBottom: .init(0xE2E7FA, 0x161743), nightCard: 0x1E1F4A
    )

    static let dinosaur = ThemePalette(
        canopy: .init(0x4D6B23, 0xB7D97E), leaf: .init(0x7AA83A, 0x93C254), lime: .init(0xD2E39B, 0x55692A),
        sunshine: .init(0xE9B93A, 0xF1CB62), mango: .init(0xE88A3A, 0xF0A462), hibiscus: .init(0xDD5E3C, 0xEC8363),
        orchid: .init(0x9474B8, 0xB399D3), lagoon: .init(0x2E9C8F, 0x58BFB2), river: .init(0x4A80B0, 0x78A6CF),
        dusk: .init(0x5E5AA8, 0x9C98DA), bark: .init(0x7A5230, 0xDCBB92),
        backgroundTop: .init(0xFBF3E1, 0x1C1910), backgroundBottom: .init(0xEDF0D2, 0x222A12), nightCard: 0x2E3420
    )

    static let princess = ThemePalette(
        canopy: .init(0xA93A7A, 0xF3A3CC), leaf: .init(0x6FC096, 0x8ED6AE), lime: .init(0xF8CFE2, 0x6E3A58),
        sunshine: .init(0xF0BC4E, 0xF6CF77), mango: .init(0xF2967A, 0xF6B09A), hibiscus: .init(0xE9558F, 0xF27CAA),
        orchid: .init(0xA672D8, 0xC59BEA), lagoon: .init(0x45AFC0, 0x70C8D6), river: .init(0x7488DE, 0x9DADEE),
        dusk: .init(0x8462CF, 0xB49CF0), bark: .init(0x8A5468, 0xE3B8C8),
        backgroundTop: .init(0xFFF0F6, 0x200F1B), backgroundBottom: .init(0xF3E8FC, 0x2A1432), nightCard: 0x3A2036
    )
}

/// The animals and little decorations of a theme.
struct ThemeArt {
    let feed, bottle, pump, sleep, tummy, diaper, weight, length, head, milestone: String
    let daycare, pickUp, vaccine, appointment, welcome: String
    /// Small icons in front of section titles.
    let logIcon, reportIcon, timelineIcon, settingsIcon, caregiversIcon, babiesIcon: String
    /// Today's header: a mascot with a little accent in the corner.
    let mascot, accent: String
    /// The friend shown when nothing's logged yet, and what it says.
    let quietAnimal, quietText: String
    /// Sign-in screen: the big mascot, three friends around it, a row below and the tagline.
    let heroFriends: [String]
    let heroRow, tagline: String
    let loading: String
    let photosEmpty: String
    let confetti: [String]

    static let jungle = ThemeArt(
        feed: "🐘", bottle: "🦒", pump: "🦩", sleep: "🐨", tummy: "🐢", diaper: "🐒", weight: "🦛", length: "🦒", head: "🐣",
        milestone: "🦁", daycare: "🦜", pickUp: "🐯", vaccine: "🦔", appointment: "🦉", welcome: "🦁",
        logIcon: "🐾", reportIcon: "🌿", timelineIcon: "🍃", settingsIcon: "🌿", caregiversIcon: "🐾", babiesIcon: "🐣",
        mascot: "🐵", accent: "🌺", quietAnimal: "🦥", quietText: "All quiet in the jungle so far today.",
        heroFriends: ["🦜", "🐒", "🌺"], heroRow: "🦁 🦒 🦛 🐯 🦩", tagline: "shared with everyone in your baby's jungle.",
        loading: "🐒", photosEmpty: "🦒📸", confetti: ["🎉", "🌺", "🍃", "⭐️", "🦁", "🌼"]
    )

    static let ocean = ThemeArt(
        feed: "🐳", bottle: "🐙", pump: "🦑", sleep: "🦭", tummy: "🐢", diaper: "🦀", weight: "🐋", length: "🦈", head: "🐚",
        milestone: "🐬", daycare: "🐠", pickUp: "🐡", vaccine: "🪼", appointment: "🦞", welcome: "🐬",
        logIcon: "🫧", reportIcon: "🐚", timelineIcon: "🌊", settingsIcon: "⚓️", caregiversIcon: "🫧", babiesIcon: "🐚",
        mascot: "🐳", accent: "🫧", quietAnimal: "🦦", quietText: "All calm under the sea so far today.",
        heroFriends: ["🐠", "🐙", "🫧"], heroRow: "🐬 🦀 🐢 🐡 🦭", tagline: "shared with everyone in your baby's ocean.",
        loading: "🐠", photosEmpty: "🐙📸", confetti: ["🎉", "🫧", "🐚", "⭐️", "🐠", "🌊"]
    )

    static let space = ThemeArt(
        feed: "🚀", bottle: "🛸", pump: "🛰️", sleep: "🌙", tummy: "🪐", diaper: "👽", weight: "🌍", length: "📏", head: "🌕",
        milestone: "⭐️", daycare: "☄️", pickUp: "🌠", vaccine: "🧑‍🚀", appointment: "🔭", welcome: "🚀",
        logIcon: "✨", reportIcon: "🪐", timelineIcon: "🌠", settingsIcon: "🛰️", caregiversIcon: "✨", babiesIcon: "🌟",
        mascot: "🧑‍🚀", accent: "⭐️", quietAnimal: "🌌", quietText: "All quiet in the galaxy so far today.",
        heroFriends: ["🪐", "🛸", "⭐️"], heroRow: "🌙 ☄️ 🌍 👽 🌠", tagline: "shared with everyone in your baby's galaxy.",
        loading: "🛸", photosEmpty: "🔭📸", confetti: ["🎉", "⭐️", "✨", "🪐", "🌟", "💫"]
    )

    static let dinosaur = ThemeArt(
        feed: "🦕", bottle: "🦖", pump: "🐊", sleep: "🥚", tummy: "🐢", diaper: "🦎", weight: "🦣", length: "🦒", head: "🐣",
        milestone: "🌋", daycare: "🌴", pickUp: "🦴", vaccine: "🦔", appointment: "🦤", welcome: "🦖",
        logIcon: "🦴", reportIcon: "🌿", timelineIcon: "🌴", settingsIcon: "🪨", caregiversIcon: "🦴", babiesIcon: "🥚",
        mascot: "🦖", accent: "🌋", quietAnimal: "🦕", quietText: "All quiet in Dino Valley so far today.",
        heroFriends: ["🌴", "🦖", "🌋"], heroRow: "🦖 🐊 🦣 🦎 🥚", tagline: "shared with everyone in your baby's dino pack.",
        loading: "🦖", photosEmpty: "🦕📸", confetti: ["🎉", "🦴", "🌿", "⭐️", "🦖", "🌋"]
    )

    static let princess = ThemeArt(
        feed: "🦄", bottle: "🫖", pump: "🦢", sleep: "🧸", tummy: "🐸", diaper: "🐰", weight: "👑", length: "🦒", head: "🎀",
        milestone: "🏰", daycare: "🎀", pickUp: "🦋", vaccine: "🪄", appointment: "🪞", welcome: "👑",
        logIcon: "💖", reportIcon: "🌸", timelineIcon: "✨", settingsIcon: "🪄", caregiversIcon: "💖", babiesIcon: "🎀",
        mascot: "👸", accent: "✨", quietAnimal: "🦢", quietText: "All quiet in the castle so far today.",
        heroFriends: ["🦋", "🐰", "✨"], heroRow: "🏰 🦢 🐸 🧸 🦋", tagline: "shared with everyone in your baby's kingdom.",
        loading: "🦄", photosEmpty: "🦄📸", confetti: ["🎉", "💖", "🌸", "⭐️", "👑", "✨"]
    )
}
