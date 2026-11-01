import NSOGCKit
import PhotosUI
import SwiftUI

struct SettingsView: View {
  @ObservedObject var library: Library
  @ObservedObject var controllers: Controllers
  @Environment(\.dismiss) private var dismiss

  @State private var newTitle = ""
  @State private var newScheme = ""
  @State private var newPlatform: Platform = .gameCube
  @State private var coverItem: PhotosPickerItem?
  @State private var coverTarget: Game?

  var body: some View {
    NavigationStack {
      List {
        Section {
          if controllers.connected.isEmpty {
            LabeledContent("Status", value: controllers.statusText)
          }
          ForEach(controllers.connected) { controller in
            HStack {
              VStack(alignment: .leading) {
                Text(controller.name)
                Text(controller.detail)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Button("Rumble", systemImage: "waveform") { controllers.identify(controller) }
                .labelStyle(.iconOnly)
              if controller.kind == .nso {
                Button("Disconnect", systemImage: "xmark.circle") { controllers.disconnect(controller) }
                  .labelStyle(.iconOnly)
              }
            }
            .buttonStyle(.borderless)
          }
          Button("Forget the NSO GameCube controllers", role: .destructive) {
            controllers.forgetNSOControllers()
          }
        } header: {
          Text("Controllers")
        } footer: {
          Text("Press SYNC on an NSO GameCube controller to pair it. Other controllers work as soon as iOS knows them. In a game, HOME opens PadHub's menu, with these settings too.")
        }

        Section("Games") {
          ForEach(library.games) { game in
            HStack {
              if let cover = library.cover(for: game) {
                Image(uiImage: cover)
                  .resizable()
                  .scaledToFill()
                  .frame(width: 28, height: 40)
                  .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
              } else {
                Image(systemName: game.symbol)
                  .foregroundStyle(game.palette.first ?? .white)
                  .frame(width: 28)
              }
              VStack(alignment: .leading) {
                Text(game.title)
                Text(
                  game.embedded != nil
                    ? "\(game.platform.label) · built into PadHub"
                    : "\(game.platform.label) · \(game.scheme)://"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              Spacer()
              Menu {
                Button("Choose Cover…", systemImage: "photo") { coverTarget = game }
                if library.covers[game.id] != nil {
                  Button("Remove Cover", systemImage: "xmark") { library.setCover(nil, for: game) }
                }
                if game.isCustom {
                  Button("Delete", systemImage: "trash", role: .destructive) { library.remove(game) }
                }
              } label: {
                Image(systemName: "ellipsis.circle")
              }
              Toggle(
                "Shown",
                isOn: Binding(
                  get: { !library.hidden.contains(game.id) },
                  set: { library.setHidden(!$0, for: game) })
              )
              .labelsHidden()
            }
          }
          .onMove(perform: library.move)
        }

        Section("Add a game") {
          TextField("Title", text: $newTitle)
          TextField("URL scheme (e.g. dusklight)", text: $newScheme)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Picker("Platform", selection: $newPlatform) {
            ForEach(Platform.allCases) { Text($0.label).tag($0) }
          }
          Button("Add") {
            library.add(title: newTitle, platform: newPlatform, scheme: newScheme)
            newTitle = ""
            newScheme = ""
          }
          .disabled(newTitle.isEmpty || newScheme.isEmpty)
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { EditButton() }
        ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
      }
      .photosPicker(
        isPresented: Binding(get: { coverTarget != nil }, set: { if !$0 { coverTarget = nil } }),
        selection: $coverItem, matching: .images)
      .onChange(of: coverItem) { _, item in
        guard let item, let game = coverTarget else { return }
        Task {
          if let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
          {
            library.setCover(image, for: game)
          }
          coverItem = nil
          coverTarget = nil
        }
      }
    }
  }
}
