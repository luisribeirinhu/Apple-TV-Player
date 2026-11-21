#if os(tvOS)
import SwiftUI

struct LiveTVSettingsView: View {
    @Bindable var viewModel: LiveTVViewModel
    let onAddPlaylist: () -> Void
    let onChangePlaylist: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var showsAddPlaylist = false
    @State private var showsPlaylistChooser = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Lista IPTV") {
                    Button("Adicionar lista") { showsAddPlaylist = true }
                    Button("Mudar de lista") { showsPlaylistChooser = true }
                    Button("Atualizar lista") {
                        Task { await viewModel.refreshPlaylist(pin: pin); pin = "" }
                    }
                    .disabled(viewModel.content == nil)
                }
                Section("Guia TV") {
                    TextField("Endereço XMLTV", text: $viewModel.epgSource)
                        .autocorrectionDisabled().textInputAutocapitalization(.never).privacySensitive()
                    Button("Guardar origem do guia") {
                        Task { await viewModel.saveEPGSource(pin: pin); pin = "" }
                    }
                    Button("Atualizar guia TV") { Task { await viewModel.refreshEPG() } }
                }
                .disabled(viewModel.content == nil)

                if viewModel.requiresPIN {
                    Section("Confirmação da lista protegida") {
                        SecureField("PIN para guardar alterações", text: $pin)
                            .privacySensitive()
                    }
                }

                Section("Reprodução") {
                    Toggle("Aguardar para reduzir interrupções", isOn: Binding(
                        get: { viewModel.preferences.waitsToMinimizeStalling },
                        set: { viewModel.setWaitsToMinimizeStalling($0) }
                    ))
                }
                Section("Três posições favoritas") {
                    ForEach(0..<LiveTVPreferences.slotCount, id: \.self) { slot in
                        Menu {
                            Button("Usar canal em reprodução") { viewModel.assign(viewModel.selectedChannel, to: slot) }
                                .disabled(viewModel.selectedChannel == nil)
                            Button("Remover", role: .destructive) { viewModel.assign(nil, to: slot) }
                        } label: {
                            Text("\(slot + 1) · \(viewModel.favoriteChannel(at: slot)?.title ?? "Vazia")")
                        }
                    }
                    Button("Limpar as três posições", role: .destructive) { viewModel.resetFavorites() }
                }
                Button("Concluir") { dismiss() }
            }
            .disabled(viewModel.isUpdating)
            .overlay {
                if viewModel.isUpdating { ProgressView("A atualizar…").padding(32).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)) }
            }
            .navigationTitle("Definições")
        }
        .onDisappear { pin = "" }
        .onChange(of: showsAddPlaylist) { _, show in
            if show { dismiss(); onAddPlaylist() }
        }
        .onChange(of: showsPlaylistChooser) { _, show in
            if show { dismiss(); onChangePlaylist() }
        }
    }
}

#Preview {
    LiveTVSettingsView(viewModel: LiveTVViewModel(), onAddPlaylist: {}, onChangePlaylist: {})
}
#endif
