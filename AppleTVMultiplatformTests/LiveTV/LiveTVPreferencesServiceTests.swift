#if os(tvOS)
import Foundation
import Testing
@testable import Bro_Player

struct LiveTVPreferencesServiceTests {
    private let a = LiveTVFavorite(playlistKey: "playlist", channelKey: "a")
    private let b = LiveTVFavorite(playlistKey: "playlist", channelKey: "b")

    @Test func hasExactlyThreeSlotsAndRejectsInvalidIndices() {
        var preferences = LiveTVPreferences()
        preferences.assign(a, to: -1)
        preferences.assign(a, to: 3)
        #expect(preferences.favorites == [nil, nil, nil])
    }

    @Test func assignsReplacesMovesAndRemovesWithoutDuplicates() {
        var preferences = LiveTVPreferences()
        preferences.assign(a, to: 0)
        preferences.assign(b, to: 1)
        preferences.assign(a, to: 2)
        #expect(preferences.favorites == [nil, b, a])
        preferences.assign(b, to: 2)
        #expect(preferences.favorites == [nil, nil, b])
        preferences.assign(nil, to: 2)
        #expect(preferences.favorites == [nil, nil, nil])
    }

    @Test func resetsAllSlots() {
        var preferences = LiveTVPreferences()
        preferences.assign(a, to: 0)
        preferences.resetFavorites()
        #expect(preferences.favorites == [nil, nil, nil])
    }

    @Test func normalizesShortOversizedAndDuplicateSavedArrays() throws {
        for (json, expected) in [
            (#"{"favorites":[]}"#, [nil, nil, nil]),
            (#"{"favorites":[{"playlistKey":"playlist","channelKey":"a"}]}"#, [a, nil, nil]),
            (#"{"favorites":[null,null,null,{"playlistKey":"playlist","channelKey":"b"}]}"#, [nil, nil, nil]),
            (#"{"favorites":[{"playlistKey":"playlist","channelKey":"a"},{"playlistKey":"playlist","channelKey":"a"}]}"#, [a, nil, nil])
        ] as [(String, [LiveTVFavorite?])] {
            let preferences = try JSONDecoder().decode(LiveTVPreferences.self, from: Data(json.utf8))
            #expect(preferences.favorites == expected)
        }
    }

    @Test func persistsAcrossServiceInstancesWithoutStoringStreamURLs() async throws {
        let suite = "LiveTVPreferencesServiceTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = LiveTVPreferences()
        preferences.assign(a, to: 1)
        preferences.lastPlaylistKey = "saved-playlist"
        preferences.waitsToMinimizeStalling = false
        try await LiveTVPreferencesService(suiteName: suite).save(preferences)
        let restored = await LiveTVPreferencesService(suiteName: suite).load()
        #expect(restored == preferences)
    }

    @Test func malformedStorageFallsBackToThreeEmptySlots() async throws {
        let suite = "LiveTVPreferencesServiceTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not JSON".utf8), forKey: "tvOS.liveTV.preferences.v1")
        let restored = await LiveTVPreferencesService(suiteName: suite).load()
        #expect(restored.favorites == [nil, nil, nil])
    }

    @Test func channelIdentitySurvivesURLRotationWhenTvgIDExists() {
        let first = PlaylistParser.Stream(title: "Canal", url: "https://example.invalid/old?token=secret",
                                          tvgLogo: nil, tvgID: "channel-id", tvgName: nil, groupTitle: nil)
        let updated = PlaylistParser.Stream(title: "Novo nome", url: "https://example.invalid/new",
                                            tvgLogo: nil, tvgID: "channel-id", tvgName: nil, groupTitle: nil)
        #expect(LiveTVFavorite.channelKey(for: first) == LiveTVFavorite.channelKey(for: updated))
        #expect(!LiveTVFavorite.channelKey(for: first).contains("secret"))
    }
}
#endif
