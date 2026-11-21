#if os(tvOS)
import AVFoundation
import AVKit
import SwiftUI

enum LiveTVFocus: Hashable {
    case channel(Int), favorite(Int), player, settings, setup
}

struct LiveTVView: View {
    let content: PlaylistItem.Content?
    let onAddPlaylist: () -> Void
    let onChangePlaylist: () -> Void
    @State private var viewModel = LiveTVViewModel()
    @State private var showsSettingsControl = false
    @State private var showsSettings = false
    @State private var showsFullScreen = false
    @State private var lastChannelFocus: Int?
    @State private var pendingSettingsAction: (() -> Void)?
    @FocusState private var focus: LiveTVFocus?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 144
            HStack(alignment: .top, spacing: 32) {
                navigation
                    .frame(width: (width - 32) * 0.35)
                LiveTVPlayerView(viewModel: viewModel, showsFullScreen: $showsFullScreen, focus: $focus)
                    .frame(width: (width - 32) * 0.65, alignment: .topLeading)
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 40)
            .overlay(alignment: .leading) {
                if showsSettingsControl {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 26))
                            .frame(width: 52, height: 64)
                    }
                    .buttonStyle(LiveTVButtonStyle())
                    .focused($focus, equals: .settings)
                    .padding(.leading, 8)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .accessibilityLabel("Definições")
                    .accessibilityIdentifier("live-settings")
                    .onMoveCommand { direction in
                        if direction == .right { hideSettingsControl() }
                    }
                    .onExitCommand { hideSettingsControl() }
                    .task { focus = .settings }
                }
            }
        }
        .background(Color(red: 0.035, green: 0.045, blue: 0.065))
        .preferredColorScheme(.dark)
        .task(id: content?.id) {
            guard let content else { return }
            await viewModel.load(content)
            if focus == nil, let first = viewModel.channels.first { focus = .channel(first.id) }
        }
        .onChange(of: focus) { _, target in
            if case let .channel(number) = target { lastChannelFocus = number }
            if target != .settings, showsSettingsControl {
                withAnimation(.easeOut(duration: 0.16)) { showsSettingsControl = false }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                viewModel.player.player.pause()
            } else if phase == .active, viewModel.selectedChannel != nil {
                viewModel.player.player.play()
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showsSettings, onDismiss: {
            hideSettingsControl()
            let action = pendingSettingsAction
            pendingSettingsAction = nil
            action?()
        }) {
            LiveTVSettingsView(viewModel: viewModel,
                               onAddPlaylist: { pendingSettingsAction = onAddPlaylist },
                               onChangePlaylist: { pendingSettingsAction = onChangePlaylist })
        }
        .fullScreenCover(isPresented: $showsFullScreen, onDismiss: { focus = .player }) {
            viewModel.player.fullScreenView()
                .onExitCommand { showsFullScreen = false }
        }
        .alert("TV em direto", isPresented: Binding(
            get: { viewModel.message != nil },
            set: { if !$0 { viewModel.message = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.message = nil }
        } message: {
            Text(viewModel.message ?? "")
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                ForEach(0..<LiveTVPreferences.slotCount, id: \.self) { slot in
                    let channel = viewModel.favoriteChannel(at: slot)
                    Button {
                        if let channel { viewModel.select(channel) }
                        else { viewModel.assign(viewModel.selectedChannel, to: slot) }
                    } label: {
                        VStack(spacing: 10) {
                            if let channel {
                                LiveTVLogoView(stream: channel.stream, logo: { await viewModel.logoURL(for: channel.stream) })
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                Text(channel.title).font(.system(size: 20, weight: .medium)).lineLimit(1)
                            } else {
                                Image(systemName: "plus").font(.system(size: 30, weight: .light))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                    }
                    .buttonStyle(LiveTVButtonStyle())
                    .focused($focus, equals: .favorite(slot))
                    .accessibilityLabel(channel.map { "Favorito \(slot + 1): \($0.title)" } ?? "Posição \(slot + 1) vazia. Adicionar canal em reprodução")
                    .accessibilityIdentifier("favorite-slot-\(slot)")
                    .contextMenu {
                        Button("Usar canal em reprodução") { viewModel.assign(viewModel.selectedChannel, to: slot) }
                            .disabled(viewModel.selectedChannel == nil)
                        Button("Remover", role: .destructive) { viewModel.assign(nil, to: slot) }
                    }
                    .onMoveCommand { direction in
                        if direction == .left, slot == 0 { revealSettingsControl() }
                    }
                }
            }
            .frame(maxHeight: 170)

            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)

            if viewModel.channels.isEmpty {
                VStack(alignment: .leading, spacing: 24) {
                    Text(viewModel.isLoading ? "A carregar canais…" : "Adicione a sua lista para começar.")
                        .foregroundStyle(.secondary)
                    Button("Adicionar lista IPTV", action: onAddPlaylist)
                        .focused($focus, equals: .setup)
                    Button("Escolher lista", action: onChangePlaylist)
                }
                .font(.system(size: 26))
                .onMoveCommand { direction in
                    if direction == .left { revealSettingsControl() }
                }
                Spacer()
            } else {
                channelList
            }
        }
        .focusSection()
    }

    private var channelList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.channels) { channel in
                        Button {
                            if viewModel.selectedChannel?.id == channel.id { showsFullScreen = true }
                            else { viewModel.select(channel) }
                        } label: {
                            LiveTVChannelRowView(channel: channel, selected: viewModel.selectedChannel?.id == channel.id,
                                                 logo: { await viewModel.logoURL(for: channel.stream) })
                        }
                        .buttonStyle(LiveTVButtonStyle())
                        .focused($focus, equals: .channel(channel.id))
                        .id(channel.id)
                        .accessibilityIdentifier("live-channel-\(channel.number)")
                        .contextMenu {
                            ForEach(0..<LiveTVPreferences.slotCount, id: \.self) { slot in
                                Button("Atribuir à posição \(slot + 1)") { viewModel.assign(channel, to: slot) }
                            }
                        }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.hidden)
            // Scoped to the one-column list. UP/DOWN/RIGHT remain native focus moves.
            .onMoveCommand { direction in
                if direction == .left, case .channel = focus { revealSettingsControl() }
            }
            .onChange(of: showsSettingsControl) { _, visible in
                if !visible, let lastChannelFocus {
                    proxy.scrollTo(lastChannelFocus, anchor: .center)
                    focus = .channel(lastChannelFocus)
                }
            }
        }
    }

    private func revealSettingsControl() {
        withAnimation(.easeOut(duration: 0.16)) { showsSettingsControl = true }
    }

    private func hideSettingsControl() {
        withAnimation(.easeOut(duration: 0.16)) { showsSettingsControl = false }
        if let lastChannelFocus { focus = .channel(lastChannelFocus) }
        else { focus = viewModel.channels.first.map { .channel($0.id) } ?? .setup }
    }
}

#Preview {
    LiveTVView(content: nil, onAddPlaylist: {}, onChangePlaylist: {})
}
#endif
