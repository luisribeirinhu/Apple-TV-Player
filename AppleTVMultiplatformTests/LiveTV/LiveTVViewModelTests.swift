#if os(tvOS)
import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import SwiftData
import Testing
@testable import Bro_Player

@MainActor
@Suite(.container)
struct LiveTVViewModelTests {
    @Test func flattensAllPlaylistsPreservingInterleavedGroupsAndDuplicateRows() async {
        let first = stream("One", group: "A")
        let second = stream("Two", group: "B")
        let third = stream("Three", group: "A")
        let vm = makeViewModel(playlists: [playlist([first, second, third]), playlist([first])])
        await vm.load(content)
        #expect(vm.channels.map(\.stream) == [first, second, third, first])
        #expect(vm.channels.map(\.number) == [1, 2, 3, 4])
        #expect(Set(vm.channels.map(\.id)).count == 4)
    }

    @Test func favoriteResolvesAgainAfterPlaylistReordering() async {
        let preferences = LiveTVPreferencesMock()
        Container.shared.liveTVPreferencesService.register { preferences }
        let service = LiveTVPlaylistMock(playlists: [playlist([stream("One"), stream("Two")])])
        Container.shared.playlistService.register { service }
        let vm = LiveTVViewModel(player: player())
        await vm.load(content)
        vm.assign(vm.channels[1], to: 0)
        #expect(vm.favoriteChannel(at: 0)?.title == "Two")
        // Allow the queued persistence write to complete before constructing the next session.
        await vm.flushPreferences()
        await service.replace([playlist([stream("Two"), stream("One")])])
        let restored = LiveTVViewModel(player: player())
        await restored.load(content)
        #expect(restored.favoriteChannel(at: 0)?.title == "Two")
        #expect(restored.favoriteChannel(at: 0)?.number == 1)
    }

    @Test func tuningReusesPlayerAndReselectingKeepsCurrentItem() async throws {
        let vm = makeViewModel(playlists: [playlist([stream("One"), stream("Two")])])
        let original = vm.player.player
        await vm.load(content)
        let firstItem = try #require(original.currentItem)
        vm.select(vm.channels[0])
        #expect(original.currentItem === firstItem)
        vm.select(vm.channels[1])
        #expect(vm.player.player === original)
        #expect(original.currentItem !== firstItem)
    }

    @Test func currentNextAndProgressRespectActualDurationAndGaps() async throws {
        let now = Date(timeIntervalSince1970: 150)
        let current = ProgramGuide.Program(title: "Agora", start: Date(timeIntervalSince1970: 100), stop: Date(timeIntervalSince1970: 300))
        let next = ProgramGuide.Program(title: "Depois", start: Date(timeIntervalSince1970: 400), stop: Date(timeIntervalSince1970: 600))
        let guide = ProgramGuide(channel: .init(id: "One", displayName: "One", iconURL: nil), programs: [next, current])
        let vm = makeViewModel(playlists: [playlist([stream("One")])], guides: ["One": guide])
        await vm.load(content)
        await vm.updatePrograms()
        #expect(vm.currentProgram(at: now) == current)
        #expect(vm.nextProgram(at: now) == next)
        #expect(LiveTVViewModel.progress(for: current, at: now) == 0.25)
        #expect(vm.currentProgram(at: current.stop) == nil)
        #expect(vm.nextProgram(at: current.stop) == next)
        #expect(LiveTVViewModel.progress(for: current, at: .distantPast) == 0)
        #expect(LiveTVViewModel.progress(for: current, at: .distantFuture) == 1)
    }

    @Test func missingEPGDoesNotRemovePlayerItem() async {
        let vm = makeViewModel(playlists: [playlist([stream("One")])])
        await vm.load(content)
        let item = vm.player.player.currentItem
        await vm.updatePrograms()
        #expect(vm.programs.isEmpty)
        #expect(vm.currentProgram(at: .now) == nil)
        #expect(vm.player.player.currentItem === item)
    }

    @Test func startupRestoresLastPlaylistAndAddingChoosesNewest() async {
        let database = DatabaseService(isStoredInMemoryOnly: true)
        Container.shared.databaseService.register { database }
        let older = PlaylistItem.Identity(name: "Anterior", date: Date(timeIntervalSince1970: 1))
        let newer = PlaylistItem.Identity(name: "Nova", date: Date(timeIntervalSince1970: 2))
        for identity in [older, newer] {
            database.mainContext.insert(PlaylistItem(name: identity.name, date: identity.date, icon: nil,
                                                    url: Data(), data: Data(), salt: nil, encrypted: false))
        }
        let preferences = LiveTVPreferencesMock()
        var saved = LiveTVPreferences()
        saved.lastPlaylistKey = LiveTVFavorite.playlistKey(for: older)
        await preferences.save(saved)
        Container.shared.liveTVPreferencesService.register { preferences }
        let vm = ContentViewModel()
        await vm.restoreLiveTVPlaylist()
        #expect(vm.selectedPlaylist == older)
        await vm.restoreLiveTVPlaylist(preferNewest: true)
        #expect(vm.selectedPlaylist == newer)
    }

    private func makeViewModel(playlists: [PlaylistParser.Playlist], guides: [String: ProgramGuide] = [:]) -> LiveTVViewModel {
        let service = LiveTVPlaylistMock(playlists: playlists, guides: guides)
        Container.shared.playlistService.register { service }
        Container.shared.liveTVPreferencesService.register { LiveTVPreferencesMock() }
        return LiveTVViewModel(player: player())
    }

    private func player() -> TvOSPlayer {
        // Empty compositions exercise AVPlayer ownership without connecting to any stream.
        TvOSPlayer(automaticallyPlays: false, makeItem: { _ in AVPlayerItem(asset: AVMutableComposition()) })
    }

    private var content: PlaylistItem.Content {
        .init(identity: .init(name: "Test", date: Date(timeIntervalSince1970: 1)), url: Data(), data: Data(), isStoredInMemoryOnly: true)
    }

    private func stream(_ name: String, group: String? = nil) -> PlaylistParser.Stream {
        .init(title: name, url: "https://example.invalid/\(name)", tvgLogo: nil, tvgID: name, tvgName: nil, groupTitle: group)
    }

    private func playlist(_ streams: [PlaylistParser.Stream]) -> PlaylistParser.Playlist {
        .init(tvgURL: nil, imageURL: nil, xTvgURL: nil, tvgLogo: nil, streams: streams)
    }
}

private actor LiveTVPreferencesMock: LiveTVPreferencesServiceInterface {
    private var preferences = LiveTVPreferences()
    func load() -> LiveTVPreferences { preferences }
    func save(_ preferences: LiveTVPreferences) { self.preferences = preferences }
}

private actor LiveTVPlaylistMock: PlaylistServiceInterface {
    var items: [PlaylistParser.Playlist]
    let guides: [String: ProgramGuide]
    init(playlists: [PlaylistParser.Playlist], guides: [String: ProgramGuide] = [:]) { items = playlists; self.guides = guides }
    func replace(_ playlists: [PlaylistParser.Playlist]) { items = playlists }
    func playlists(for content: PlaylistItem.Content, reloadProgramGuide: Bool, progress: @escaping ProgressHandler) -> [PlaylistParser.Playlist] { items }
    func playlists(for content: PlaylistItem.Content, reloadPlaylist: Bool, progress: @escaping ProgressHandler) -> [PlaylistParser.Playlist] { items }
    func programGuide(for content: PlaylistItem.Content, stream: PlaylistParser.Stream) -> ProgramGuide? { guides[stream.title] }
    func programGuides(for content: PlaylistItem.Content, since: Date) -> [ProgramGuide] { Array(guides.values) }
    func clearCache(for content: PlaylistItem.Content) {}
}
#endif
