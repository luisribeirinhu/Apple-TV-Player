
import SwiftUI
import FactoryKit
import SwiftData

@Observable
final class ContentViewModel {

    @ObservationIgnored @Injected(\.databaseService) private var databaseService
    @ObservationIgnored @Injected(\.playlistAddService) private var playlistAddService
    @ObservationIgnored @Injected(\.logger) private var logger

    var selectedPlaylist: PlaylistItem.Identity?
    var selectedPlaylistContent: PlaylistItem.Content?
    var selectedPlaylistStream: PlaylistParser.Stream?
    var isShowingPlaylistAdd = false
    var isShowingPlaylistDecryptPin: PlaylistItem.Identity?
#if os(tvOS)
    var path: [PlaylistItem.Content] = []
    private(set) var liveTVPlaylists: [PlaylistItem.Identity] = []

    func loadLiveTVPlaylists() {
        let fetch = FetchDescriptor<PlaylistItem>(sortBy: [.init(\.date, order: .reverse)])
        liveTVPlaylists = ((try? databaseService.mainContext.fetch(fetch)) ?? []).compactMap(\.identity)
    }

    func restoreLiveTVPlaylist(preferNewest: Bool = false) async {
        loadLiveTVPlaylists()
        guard preferNewest || selectedPlaylist == nil else { return }
        let preferences = await Container.shared.liveTVPreferencesService().load()
        let saved = liveTVPlaylists.first { LiveTVFavorite.playlistKey(for: $0) == preferences.lastPlaylistKey }
        let identity = preferNewest ? liveTVPlaylists.first : (saved ?? liveTVPlaylists.first)
        if let identity, selectedPlaylist != identity { selectedPlaylist = identity }
    }
#endif
    private(set) var playlistListUpdate = UUID()

    func onPlaylistSelected() async {
        selectedPlaylistContent = nil
        selectedPlaylistStream = nil
        isShowingPlaylistDecryptPin = nil

        guard let identity = selectedPlaylist else {
            logger.error("Playlist delected")
            return
        }
        logger.info("Playlist selected", private: identity)
        do {
            let fetch = FetchDescriptor<PlaylistItem>()
            guard let playlist = (try databaseService.mainContext.fetch(fetch))
                .first(where: { $0.identity == identity }) else {
                return
            }

            guard let preparedPlaylist = PreparedPlaylist(playlist) else {
                return
            }

            if playlist.encrypted {
                selectedPlaylistContent = nil
#if os(tvOS)
                path = []
#endif
                logger.info("Show enter pin to decrypt", private: identity)
                isShowingPlaylistDecryptPin = identity
            } else {
                let restoredPlaylist = try await playlistAddService.restorePlaylist(preparedPlaylist, pin: nil)
                guard !Task.isCancelled, selectedPlaylist == identity else { return }
                logger.info("Show Playlist", private: identity)
                selectedPlaylistContent = restoredPlaylist.content
#if os(tvOS)
                path = [restoredPlaylist.content]
#endif
            }
        } catch {
            logger.error(error)
        }
    }

    func onDecrypt() {
        if let selectedPlaylistContent {
            logger.info("Show Playlist", private: selectedPlaylistContent.identity)
#if os(tvOS)
            path = [selectedPlaylistContent]
#endif
        } else {
            selectedPlaylist = nil
        }
    }

    func updatePlaylists() {
        logger.info("Update Playlists")
        playlistListUpdate = .init()
    }
    
    func onAddPlaylist() {
        logger.info("Show Add Playlist")
        isShowingPlaylistAdd = true
    }

    isolated deinit {
        logger.info("deinit of \(self)")
    }
}
