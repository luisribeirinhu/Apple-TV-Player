#if os(tvOS)
import AVFoundation
import AVKit
import SwiftUI

struct LiveTVPlayerView: View {
    let viewModel: LiveTVViewModel
    @Binding var showsFullScreen: Bool
    var focus: FocusState<LiveTVFocus?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Button {
                showsFullScreen = true
            } label: {
                ZStack {
                    Color.black
                    // Only one AVPlayerViewController owns the rendering surface at a time.
                    if viewModel.selectedChannel != nil, !showsFullScreen {
                        TvOSPlayerView(player: viewModel.player.player, compact: true)
                            .allowsHitTesting(false)
                    } else if viewModel.selectedChannel == nil {
                        Image(systemName: "play.tv").font(.system(size: 70, weight: .ultraLight)).foregroundStyle(.secondary)
                    }
                    if let error = viewModel.player.errorMessage {
                        Text(error).font(.system(size: 24)).padding(32).background(.black.opacity(0.8))
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(LiveTVButtonStyle())
            .focused(focus, equals: .player)
            .disabled(viewModel.selectedChannel == nil)
            .accessibilityLabel("Abrir reprodução em ecrã inteiro")
            .accessibilityIdentifier("live-player")
            .onPlayPauseCommand {
                let player = viewModel.player.player
                if player.rate == 0 { player.play() } else { player.pause() }
            }

            Text(viewModel.selectedChannel?.title ?? "TV em direto")
                .font(.system(size: 36, weight: .semibold)).lineLimit(1)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 16) {
                    if let current = viewModel.currentProgram(at: context.date) {
                        Text(current.title).font(.system(size: 30, weight: .medium)).lineLimit(2)
                        HStack {
                            Text(current.start, style: .time)
                            Spacer()
                            Text(current.stop, style: .time)
                        }
                        .font(.system(size: 23)).foregroundStyle(.secondary).monospacedDigit()
                        ProgressView(value: LiveTVViewModel.progress(for: current, at: context.date))
                            .tint(.blue)
                    } else {
                        Text("Informação do programa indisponível")
                            .font(.system(size: 26)).foregroundStyle(.secondary)
                    }
                    if let next = viewModel.nextProgram(at: context.date) {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(next.start, style: .time).monospacedDigit()
                            Text("A seguir · \(next.title)").lineLimit(2)
                        }
                        .font(.system(size: 24)).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    LiveTVView(content: nil, onAddPlaylist: {}, onChangePlaylist: {})
}
#endif
