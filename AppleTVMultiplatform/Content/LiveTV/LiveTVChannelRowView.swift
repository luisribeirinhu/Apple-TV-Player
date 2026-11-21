#if os(tvOS)
import FactoryKit
import NukeUI
import SwiftUI

struct LiveTVChannelRowView: View {
    let channel: LiveTVViewModel.Channel
    let selected: Bool
    var logo: @MainActor () async -> URL? = { nil }

    var body: some View {
        HStack(spacing: 14) {
            Text(String(format: "%03d", channel.number))
                .font(.system(size: 22, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52)
            LiveTVLogoView(stream: channel.stream, logo: logo).frame(width: 58, height: 44)
            Text(channel.title).font(.system(size: 28, weight: .medium)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if selected { Image(systemName: "speaker.wave.2.fill").font(.system(size: 18)).foregroundStyle(.blue) }
        }
        .padding(.horizontal, 16)
        .frame(height: 76)
        .background(selected ? Color.blue.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.blue : .clear, lineWidth: 2) }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct LiveTVLogoView: View {
    let stream: PlaylistParser.Stream
    var logo: @MainActor () async -> URL? = { nil }
    @State private var logoURL: URL?

    var body: some View {
        LazyImage(url: logoURL) { state in
            if let image = state.image {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "tv").resizable().scaledToFit().foregroundStyle(.secondary).padding(8)
            }
        }
        .accessibilityHidden(true)
        .task(id: stream.id) {
            if let logo = stream.tvgLogo, let url = URL(string: logo) {
                logoURL = url
            } else {
                logoURL = await logo()
            }
        }
    }
}

struct LiveTVButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Color(white: isFocused ? 0.20 : 0.10), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(isFocused ? Color.blue : .clear, lineWidth: 4)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

#Preview {
    LiveTVChannelRowView(channel: .init(number: 1, stream: .init(title: "Canal de exemplo", url: "https://example.com/live.m3u8", tvgLogo: nil, tvgID: nil, tvgName: nil, groupTitle: nil), favoriteKey: "preview"), selected: true)
}
#endif
