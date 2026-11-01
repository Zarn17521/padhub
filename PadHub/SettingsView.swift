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
          LabeledContent("Status", value: controllers.statusText)
          Button("Forget the NSO GameCube controller", role: .destructive) {
            NSOGCManager.shared.forgetControllers()
          }
        } header: {
          Text("Controller")
        } footer: {
          Text("Press SYNC on an NSO GameCube controller to pair it. Other controllers work as soon as iOS knows them.")
        }

        Section("Games") {
          ForEach(library.games) { game in
            HStack {
              Image(systemName: game.symbol)
                .foregroundStyle(game.palette.first ?? .white)
                .frame(width: 28)
              VStack(alignment: .leading) {
                Text(game.title)
                Text("\(game.platform.label) · \(game.scheme)://")
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
