#if os(macOS) && arch(arm64)
  import SwiftUI
  import ThistleSupport

  struct PDFStampEditor: View {
    @Binding var stamps: [PDFStamp]
    let enabled: Bool
    @State private var picker: FileSlotPicker?
    @State private var importError: String?

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Stamps").font(.headline)
          Spacer()
          Button("Add stamp", systemImage: "plus") {
            stamps.append(PDFStamp(text: "APPROVED"))
          }
          .accessibilityLabel("Add stamp")
        }
        Text("Applied in the order shown. Positions use points from the bottom-left of each page.")
          .font(.caption).foregroundStyle(.secondary)
        ForEach($stamps) { $stamp in
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("Stamp \((stamps.firstIndex(where: { $0.id == stamp.id }) ?? 0) + 1)")
                .font(.headline)
              Spacer()
              Button {
                move(stamp.id, by: -1)
              } label: {
                Image(systemName: "arrow.up")
              }
              .help("Move up")
              .accessibilityLabel("Move stamp up")
              .disabled(stamps.first?.id == stamp.id)
              Button {
                move(stamp.id, by: 1)
              } label: {
                Image(systemName: "arrow.down")
              }
              .help("Move down")
              .accessibilityLabel("Move stamp down")
              .disabled(stamps.last?.id == stamp.id)
              Button {
                stamps.removeAll { $0.id == stamp.id }
              } label: {
                Image(systemName: "trash")
              }
              .help("Remove stamp")
              .accessibilityLabel("Remove stamp")
              .disabled(stamps.count == 1)
            }
            Picker("Kind", selection: $stamp.kind) {
              ForEach(PDFStamp.Kind.allCases) { kind in
                Text(kind.label).tag(kind)
              }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Stamp kind")
            if stamp.kind == .text {
              TextField("Text", text: $stamp.text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Stamp text")
            } else {
              let slot = assetSlot(for: stamp.kind)
              FileWell(slot: slot, files: $stamp.files, enabled: enabled) {
                let id = stamp.id
                picker = FileSlotPicker(slot: slot) { result in
                  defer { picker = nil }
                  guard let result else { return }
                  switch result {
                  case .success(let urls):
                    guard let index = stamps.firstIndex(where: { $0.id == id }) else { return }
                    if let message = slot.rejection(for: urls) {
                      importError = message
                      return
                    }
                    stamps[index].files = Array(urls.prefix(1))
                    importError = nil
                  case .failure(let error):
                    importError = error.localizedDescription
                  }
                }
                picker?.present()
              }
            }
            TextField("Pages", text: $stamp.pages, prompt: Text("all"))
              .textFieldStyle(.roundedBorder)
              .accessibilityLabel("Pages")
              .help("all, odd, even, or ranges such as 1-3,5")
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
              GridRow {
                Text("X").font(.caption).foregroundStyle(.secondary)
                TextField("X", text: $stamp.x).textFieldStyle(.roundedBorder)
                Text("Y").font(.caption).foregroundStyle(.secondary)
                TextField("Y", text: $stamp.y).textFieldStyle(.roundedBorder)
              }
              GridRow {
                Text("Font size").font(.caption).foregroundStyle(.secondary)
                TextField("Font size", text: $stamp.fontSize).textFieldStyle(.roundedBorder)
                if stamp.kind == .text {
                  Text("Font").font(.caption).foregroundStyle(.secondary)
                  Picker("Font", selection: $stamp.font) {
                    ForEach(PDFStamp.standardFonts, id: \.self) { name in
                      Text(name).tag(name)
                    }
                  }
                  .labelsHidden()
                }
              }
              if stamp.kind == .text {
                GridRow {
                  Text("Color").font(.caption).foregroundStyle(.secondary)
                  TextField("Color", text: $stamp.color).textFieldStyle(.roundedBorder)
                  Text("Opacity").font(.caption).foregroundStyle(.secondary)
                  TextField("Opacity", text: $stamp.opacity).textFieldStyle(.roundedBorder)
                }
              }
              GridRow {
                Text("Rotation").font(.caption).foregroundStyle(.secondary)
                TextField("Rotation", text: $stamp.rotation).textFieldStyle(.roundedBorder)
                if stamp.kind != .text {
                  Text("Scale").font(.caption).foregroundStyle(.secondary)
                  TextField("Scale", text: $stamp.scale).textFieldStyle(.roundedBorder)
                }
              }
              if stamp.kind == .pdf {
                GridRow {
                  Text("Source page").font(.caption).foregroundStyle(.secondary)
                  TextField("Source page", text: $stamp.sourcePage).textFieldStyle(.roundedBorder)
                }
              }
            }
            if let message = stamp.validationMessage {
              Text(message).font(.caption).foregroundStyle(.red)
            }
          }
          .padding(14)
          .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        }
        if let importError { Text(importError).font(.caption).foregroundStyle(.red) }
      }
      .disabled(!enabled)
    }

    private func move(_ id: UUID, by offset: Int) {
      guard let index = stamps.firstIndex(where: { $0.id == id }),
        stamps.indices.contains(index + offset)
      else { return }
      stamps.swapAt(index, index + offset)
    }

    private func assetSlot(for kind: PDFStamp.Kind) -> FileSlot {
      let pdf = kind == .pdf
      return FileSlot(
        field: "files", label: pdf ? "Stamp PDF" : "Stamp image",
        types: pdf ? ConvertUTType.pdf : ConvertUTType.images, allowsMultiple: false,
        help: pdf ? "One PDF used as the stamp." : "PNG or JPEG.",
        extensions: pdf ? ConvertUTType.pdfExtensions : ["png", "jpg", "jpeg"])
    }
  }
#endif
