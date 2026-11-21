
import SwiftUI
import SwiftData
import FactoryKit

struct ContentView: View {

    @Binding var playlistListUpdate: UUID
    @State private var viewModel = ContentViewModel()
    @InjectedObservable(\.logger) var logger
#if os(tvOS)
    @State private var showsPlaylistChooser = false
#endif
    @State private var reloadCurrentProgram: UUID = .init()

    var body: some View {
        contentView()
            .sheet(isPresented: $viewModel.isShowingPlaylistAdd) {
                addPlaylistView()
                    .onDisappear {
                        viewModel.updatePlaylists()
#if os(tvOS)
                        Task { await viewModel.restoreLiveTVPlaylist(preferNewest: true) }
#endif
                    }
            }
#if os(tvOS)
            .task(id: viewModel.selectedPlaylist) { await viewModel.onPlaylistSelected() }
#else
            .onChange(of: viewModel.selectedPlaylist) {
                Task {
                    await viewModel.onPlaylistSelected()
                }
            }
#endif
            .onChange(of: playlistListUpdate) {
                viewModel.updatePlaylists()
            }
            .sheet(item: $viewModel.isShowingPlaylistDecryptPin, onDismiss: {
                viewModel.onDecrypt()
            }) { identity in
#if os(iOS)
                NavigationStack {
                    pinCodeSheet(identity)
                }
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled(true)
#else
                pinCodeSheet(identity)
                    .interactiveDismissDisabled(true)
#endif
            }
    }

    private func pinCodeSheet(_ identity: PlaylistItem.Identity) -> some View {
        PlaylistsEnterPinDecryptView(
            identity: identity,
            selectedPlaylistContent: $viewModel.selectedPlaylistContent
        )
    }
    
    private func addPlaylistView() -> some View {
#if os(iOS)
        NavigationStack {
            PlaylistAddView()
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .presentationDetents([.large])

#else
        PlaylistAddView()
#endif
    }
#if os(tvOS)
    private func contentView() -> some View {
        LiveTVView(
            content: viewModel.selectedPlaylistContent,
            onAddPlaylist: { viewModel.onAddPlaylist() },
            onChangePlaylist: { showsPlaylistChooser = true }
        )
        .task { await viewModel.restoreLiveTVPlaylist() }
        .sheet(isPresented: $showsPlaylistChooser) {
            NavigationStack {
                List(viewModel.liveTVPlaylists) { identity in
                    Button(identity.name) {
                        viewModel.selectedPlaylist = identity
                        showsPlaylistChooser = false
                    }
                }
                .navigationTitle("Escolher lista")
                .task { viewModel.loadLiveTVPlaylists() }
            }
        }
    }
#else
    private func contentView() -> some View {
        NavigationSplitView(sidebar: {
            _sidebarView()
        }, content: {
            _contentView()
    #if os(macOS)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 400)
    #endif
        }, detail: {
            _detailView()
        })
#if os(macOS)
        .navigationTitle(viewModel.selectedPlaylistStream?.title ?? viewModel.selectedPlaylist?.name ?? "")
#endif
    }

    @ViewBuilder
    private func _sidebarView() -> some View {
        PlaylistsView(
            selectedPlaylist: $viewModel.selectedPlaylist
        )
        .accessibilityIdentifier("sidebar")
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 280)
#endif
#if os(iOS)
        .navigationBarTitle(String(localized: "Playlists"))
#endif
        .toolbar {
            ToolbarItem {
                AddButtonView {
                    viewModel.onAddPlaylist()
                }
            }
        }
        .id(viewModel.playlistListUpdate)
    }

    @ViewBuilder
    private func _contentView() -> some View {
        if let content = viewModel.selectedPlaylistContent {
            PlaylistView(
                content: content,
                selectedStream: $viewModel.selectedPlaylistStream,
                reloadCurrentProgram: $reloadCurrentProgram
            )
            .id(content.id)
            .accessibilityIdentifier("content")
#if os(iOS)
            .navigationBarTitle(viewModel.selectedPlaylist?.name ?? "")
#endif
        } else {
            VStack {
                Spacer()
                Text("Select a playlist")
                    .accessibilityIdentifier("select-playlist")
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func _detailView() -> some View {
        if let stream = viewModel.selectedPlaylistStream,
           let content = viewModel.selectedPlaylistContent {
            StreamView(content: content, stream: stream, reloadCurrentProgram: $reloadCurrentProgram)
                .id(stream)
                .accessibilityIdentifier("details")
        }
    }
#endif
}

#if DEBUG

import SwiftData

struct ContentViewPreviews: PreviewProvider {
    
    static var previews: some View {
        Container.shared { container in
            container.databaseService.register {
                let database = DatabaseService(isStoredInMemoryOnly: true)
                let now = Date()
                let mainContext = database.mainContext
                mainContext.insert(
                    PlaylistItem(
                        name: "Netflix", date: now.addingTimeInterval(100),
                        icon: nil, url: Data(),
                        data: Data(), salt: nil, encrypted: false
                    )
                )
                mainContext.insert(
                    PlaylistItem(
                        name: "Amazon TV", date: now.addingTimeInterval(103),
                        icon: nil, url: Data(),
                        data: Data(), salt: nil, encrypted: false
                    )
                )
                mainContext.insert(
                    PlaylistItem(
                        name: "America TV", date: now.addingTimeInterval(200),
                        icon: "https://raw.githubusercontent.com/mikehouse/Apple-TV-Player/refs/heads/master/logo.png",
                        url: Data(),
                        data: Data(), salt: nil, encrypted: false
                    )
                )
                return database
            }
        }
        ContentView(playlistListUpdate: .constant(.init()))
#if os(tvOS)
            .background(Color.init(uiColor: .darkGray))
#endif
    }
}

#endif
