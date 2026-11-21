#if os(tvOS)
import FactoryKit
import Foundation
import Observation
import SwiftData

@Observable
final class LiveTVViewModel {
    nonisolated struct Channel: Identifiable, Equatable, Sendable {
        let number: Int
        let stream: PlaylistParser.Stream
        let favoriteKey: String
        var id: Int { number }
        var title: String {
            let name = stream.tvgName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return name?.isEmpty == false ? name! : stream.title
        }
    }

    @ObservationIgnored @Injected(\.playlistService) private var playlistService
    @ObservationIgnored @Injected(\.playlistAddService) private var playlistAddService
    @ObservationIgnored @Injected(\.databaseService) private var databaseService
    @ObservationIgnored @Injected(\.liveTVPreferencesService) private var preferencesService
    @ObservationIgnored private var guideTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var channelIndex: [String: Channel] = [:]

    let player: TvOSPlayer
    private(set) var content: PlaylistItem.Content?
    private(set) var channels: [Channel] = []
    private(set) var selectedChannel: Channel?
    private(set) var programs: [ProgramGuide.Program] = []
    private(set) var preferences = LiveTVPreferences()
    private(set) var isLoading = false
    private(set) var isUpdating = false
    private(set) var requiresPIN = false
    var message: String?
    var epgSource = ""
    @ObservationIgnored private var mainPlaylist: PlaylistParser.Playlist?

    init(player: TvOSPlayer = TvOSPlayer()) {
        self.player = player
    }

    func load(_ content: PlaylistItem.Content) async {
        let request = UUID()
        generation = request
        isLoading = true
        defer { if generation == request { isLoading = false } }
        preferences = await preferencesService.load()
        player.player.automaticallyWaitsToMinimizeStalling = preferences.waitsToMinimizeStalling
        do {
            let playlists = try await playlistService.playlists(for: content, reloadProgramGuide: false, progress: { _, _ in })
            let rows = await Self.makeChannels(playlists)
            guard !Task.isCancelled, generation == request else { return }
            self.content = content
            mainPlaylist = playlists.first
            epgSource = mainPlaylist?.tvgURL ?? mainPlaylist?.xTvgURL ?? ""
            channels = rows
            channelIndex = Dictionary(rows.map { ($0.favoriteKey, $0) }, uniquingKeysWith: { first, _ in first })
            requiresPIN = storedPlaylist?.encrypted ?? false
            preferences.lastPlaylistKey = LiveTVFavorite.playlistKey(for: content.identity)
            persistPreferences()
            if let selectedChannel,
               let restored = channelIndex[selectedChannel.favoriteKey] {
                select(restored)
            } else if let first = rows.first {
                select(first)
            } else {
                message = "A lista não contém canais."
            }
        } catch {
            guard generation == request else { return }
            message = "Não foi possível carregar a lista. Verifique a origem nas definições."
        }
    }

    nonisolated private static func makeChannels(_ playlists: [PlaylistParser.Playlist]) async -> [Channel] {
        await Task.detached(priority: .userInitiated) {
            playlists.flatMap(\.streams).enumerated().map { index, stream in
                Channel(number: index + 1, stream: stream, favoriteKey: LiveTVFavorite.channelKey(for: stream))
            }
        }.value
    }

    func select(_ channel: Channel) {
        guard content != nil else { return }
        let changed = selectedChannel?.stream.id != channel.stream.id
        selectedChannel = channel
        if changed { programs = [] }
        player.tune(urlString: channel.stream.url)
        guideTask?.cancel()
        guideTask = Task { [weak self] in await self?.updatePrograms() }
    }

    func updatePrograms() async {
        guard let content, let channel = selectedChannel else { return }
        let guide = await playlistService.programGuide(for: content, stream: channel.stream)
        guard !Task.isCancelled, self.content?.id == content.id,
              selectedChannel?.stream.id == channel.stream.id else { return }
        programs = guide?.programs.sorted { $0.start < $1.start } ?? []
    }

    func logoURL(for stream: PlaylistParser.Stream) async -> URL? {
        if let source = stream.tvgLogo, let url = URL(string: source) { return url }
        guard let content else { return nil }
        let source = await playlistService.programGuide(for: content, stream: stream)?.channel.iconURL
        return source.flatMap(URL.init(string:))
    }

    func favoriteChannel(at slot: Int) -> Channel? {
        guard preferences.favorites.indices.contains(slot), let content,
              let favorite = preferences.favorites[slot],
              favorite.playlistKey == LiveTVFavorite.playlistKey(for: content.id) else { return nil }
        return channelIndex[favorite.channelKey]
    }

    func assign(_ channel: Channel?, to slot: Int) {
        let reference = channel.flatMap { channel in
            content.map { LiveTVFavorite(playlistKey: LiveTVFavorite.playlistKey(for: $0.id), channelKey: channel.favoriteKey) }
        }
        preferences.assign(reference, to: slot)
        persistPreferences()
    }

    func resetFavorites() {
        preferences.resetFavorites()
        persistPreferences()
    }

    func setWaitsToMinimizeStalling(_ enabled: Bool) {
        preferences.waitsToMinimizeStalling = enabled
        player.player.automaticallyWaitsToMinimizeStalling = enabled
        persistPreferences()
    }

    private func persistPreferences() {
        let previous = saveTask
        let snapshot = preferences
        saveTask = Task { [preferencesService] in
            await previous?.value
            try? await preferencesService.save(snapshot)
        }
    }

    func flushPreferences() async {
        await saveTask?.value
    }

    func refreshPlaylist(pin: String) async {
        guard !isUpdating, let content, let source = String(data: content.url, encoding: .utf8) else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            try await validatePIN(pin)
            let prepared = try await playlistAddService.preparePlaylist(
                name: content.id.name, urlString: source, pin: nil,
                urlTvg: mainPlaylist?.tvgURL ?? mainPlaylist?.xTvgURL,
                urlImg: mainPlaylist?.imageURL, tvgLogo: mainPlaylist?.tvgLogo,
                progress: { _, _ in }
            )
            let restored = try await playlistAddService.restorePlaylist(prepared, pin: nil)
            try await savePlaylistData(restored.data, pin: pin)
        } catch {
            message = "Não foi possível atualizar a lista. Verifique o endereço, a ligação e o PIN, se aplicável."
        }
    }

    func refreshEPG() async {
        guard !isUpdating, let content else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            _ = try await playlistService.playlists(for: content, reloadProgramGuide: true, progress: { _, _ in })
            if let selectedChannel { select(selectedChannel) }
        } catch {
            message = "Não foi possível atualizar o guia TV."
        }
    }

    func saveEPGSource(pin: String) async {
        guard !isUpdating, let content else { return }
        isUpdating = true
        defer { isUpdating = false }
        let source = epgSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.isEmpty || (URL(string: source)?.host != nil &&
              ["http", "https"].contains(URL(string: source)?.scheme?.lowercased() ?? "")),
              !source.contains(where: { $0 == "\"" || $0.isNewline }) else {
            message = "Introduza um endereço HTTP ou HTTPS válido para o guia TV."
            return
        }
        do {
            try await validatePIN(pin)
            let data = try await PlaylistParser(data: content.data).replacingProgramGuideSource(source)
            try await savePlaylistData(data, pin: pin)
        } catch {
            message = "Não foi possível guardar a origem do guia TV. Verifique o PIN, se aplicável."
        }
    }

    private var storedPlaylist: PlaylistItem? {
        guard let content else { return nil }
        return (try? databaseService.mainContext.fetch(FetchDescriptor<PlaylistItem>()))?.first { $0.identity == content.id }
    }

    private func validatePIN(_ pin: String) async throws {
        if let playlist = storedPlaylist, playlist.encrypted, let prepared = PreparedPlaylist(playlist) {
            _ = try await playlistAddService.restorePlaylist(prepared, pin: pin)
        }
    }

    private func savePlaylistData(_ data: Data, pin: String) async throws {
        guard let content, let playlist = storedPlaylist else { throw PlaylistAddService.Error.invalidPreparedPlaylist }
        let parsed = try await PlaylistParser(data: data).parse()
        guard parsed.contains(where: { !$0.streams.isEmpty }) else { throw PlaylistAddService.Error.invalidPlaylist }
        let compressed = try await DataCompressor().compress(data)
        let persistedData: Data
        if playlist.encrypted {
            let prepared = PreparedPlaylist(name: content.id.name, date: content.id.date, icon: playlist.icon,
                                            url: content.url, data: compressed, salt: playlist.salt, encrypted: false)
            persistedData = try await playlistAddService.encryptPlaylist(prepared, pin: pin).data
        } else {
            persistedData = compressed
        }
        playlist.data = persistedData
        try databaseService.mainContext.save()
        let updated = PlaylistItem.Content(identity: content.id, url: content.url, data: data,
                                           isStoredInMemoryOnly: content.isStoredInMemoryOnly)
        _ = try await playlistService.playlists(for: updated, reloadPlaylist: true, progress: { _, _ in })
        await load(updated)
    }

    // These queries use absolute dates from XMLTV. Formatting uses the device's zone.
    func currentProgram(at now: Date) -> ProgramGuide.Program? {
        programs.first { $0.start <= now && now < $0.stop }
    }

    func nextProgram(at now: Date) -> ProgramGuide.Program? {
        let boundary = currentProgram(at: now)?.stop ?? now
        return programs.first { $0.start >= boundary && $0.start > now }
    }

    nonisolated static func progress(for program: ProgramGuide.Program, at now: Date) -> Double {
        let duration = program.stop.timeIntervalSince(program.start)
        guard duration > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(program.start) / duration))
    }
}
#endif
