#if os(tvOS)
import CryptoKit
import FactoryKit
import Foundation

nonisolated struct LiveTVFavorite: Codable, Equatable, Sendable {
    let playlistKey: String
    let channelKey: String

    static func playlistKey(for identity: PlaylistItem.Identity) -> String {
        digest("\(identity.date.timeIntervalSince1970):\(identity.name)")
    }

    static func channelKey(for stream: PlaylistParser.Stream) -> String {
        let id = stream.tvgID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Store fingerprints only, never a stream URL that may contain credentials.
        return digest(id.isEmpty ? "url:\(stream.url):\(stream.title)" : "id:\(id)")
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated struct LiveTVPreferences: Codable, Equatable, Sendable {
    static let slotCount = 3
    private(set) var favorites: [LiveTVFavorite?] = Array(repeating: nil, count: slotCount)
    var lastPlaylistKey: String?
    var waitsToMinimizeStalling = true

    mutating func assign(_ favorite: LiveTVFavorite?, to slot: Int) {
        guard favorites.indices.contains(slot) else { return }
        if let favorite {
            for index in favorites.indices where favorites[index] == favorite {
                favorites[index] = nil
            }
        }
        favorites[slot] = favorite
    }

    mutating func resetFavorites() {
        favorites = Array(repeating: nil, count: Self.slotCount)
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let saved = try values.decodeIfPresent([LiveTVFavorite?].self, forKey: .favorites) ?? []
        favorites = Array(saved.prefix(Self.slotCount))
        favorites += Array(repeating: nil, count: Self.slotCount - favorites.count)
        var seen = Set<String>()
        for index in favorites.indices {
            if let favorite = favorites[index],
               !seen.insert(favorite.playlistKey + ":" + favorite.channelKey).inserted {
                favorites[index] = nil
            }
        }
        lastPlaylistKey = try values.decodeIfPresent(String.self, forKey: .lastPlaylistKey)
        waitsToMinimizeStalling = try values.decodeIfPresent(Bool.self, forKey: .waitsToMinimizeStalling) ?? true
    }
}

protocol LiveTVPreferencesServiceInterface: AnyObject, Sendable {
    func load() async -> LiveTVPreferences
    func save(_ preferences: LiveTVPreferences) async throws
}

actor LiveTVPreferencesService: LiveTVPreferencesServiceInterface {
    private let defaults: UserDefaults
    private let key = "tvOS.liveTV.preferences.v1"

    nonisolated init(suiteName: String? = nil) {
        if let suiteName {
            self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        } else {
            self.defaults = .standard
        }
    }

    func load() -> LiveTVPreferences {
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(LiveTVPreferences.self, from: data) else {
            return LiveTVPreferences()
        }
        return preferences
    }

    func save(_ preferences: LiveTVPreferences) throws {
        defaults.set(try JSONEncoder().encode(preferences), forKey: key)
    }
}

extension FactoryKit.Container {
    @MainActor var liveTVPreferencesService: Factory<LiveTVPreferencesServiceInterface> {
        self { LiveTVPreferencesService() }.singleton
    }
}
#endif
