#if os(macOS) && arch(arm64)
  import SwiftUI
  import ThistleSupport

  struct PDFMarkEditor: View {
    let prefix: String
    @Binding var marks: [PDFMark]
    let enabled: Bool
    @State private var picker: FileSlotPicker?
    @State private var importError: String?

    private var title: String { prefix == "stamp" ? "Stamp" : "Watermark" }

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("\(title)s").font(.headline)
          Spacer()
          Button("Add \(title.lowercased())", systemImage: "plus") {
            marks.append(PDFMark(text: title == "Stamp" ? "APPROVED" : "CONFIDENTIAL"))
          }
        }
        Text("Applied in the order shown. Multiple marks require Gotenberg 8.36.0 or later.")
          .font(.caption).foregroundStyle(.secondary)
        ForEach($marks) { $mark in
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("\(title) \((marks.firstIndex(where: { $0.id == mark.id }) ?? 0) + 1)")
                .font(.headline)
              Spacer()
              Button {
                move(mark.id, by: -1)
              } label: {
                Image(systemName: "arrow.up")
              }
              .help("Move up")
              .disabled(marks.first?.id == mark.id)
              Button {
                move(mark.id, by: 1)
              } label: {
                Image(systemName: "arrow.down")
              }
              .help("Move down")
              .disabled(marks.last?.id == mark.id)
              Button {
                marks.removeAll { $0.id == mark.id }
              } label: {
                Image(systemName: "trash")
              }
              .help("Remove \(title.lowercased())")
              .disabled(marks.count == 1)
            }
            Picker("Source", selection: $mark.source) {
              ForEach(PDFMark.Source.allCases) { source in Text(source.label).tag(source) }
            }
            .pickerStyle(.segmented)
            if mark.source == .text {
              TextField("Text", text: $mark.text).textFieldStyle(.roundedBorder)
            } else {
              let slot = fileSlot(source: mark.source)
              FileWell(slot: slot, files: $mark.files, enabled: enabled) {
                let id = mark.id
                picker = FileSlotPicker(slot: slot) { result in
                  defer { picker = nil }
                  guard let result else { return }
                  switch result {
                  case .success(let urls):
                    guard let index = marks.firstIndex(where: { $0.id == id }) else { return }
                    if let message = slot.rejection(for: urls) {
                      importError = message
                      return
                    }
                    marks[index].files = Array(urls.prefix(1))
                    importError = nil
                  case .failure(let error): importError = error.localizedDescription
                  }
                }
                picker?.present()
              }
            }
            TextField("Pages (all pages when empty)", text: $mark.pages)
              .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 4) {
              Text("Options JSON (optional)").font(.caption).foregroundStyle(.secondary)
              JSONTextEditor(text: $mark.options)
                .frame(minHeight: 80)
                .padding(4)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
            if let message = mark.validationMessage {
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
      guard let index = marks.firstIndex(where: { $0.id == id }),
        marks.indices.contains(index + offset)
      else { return }
      marks.swapAt(index, index + offset)
    }

    private func fileSlot(source: PDFMark.Source) -> FileSlot {
      let pdf = source == .pdf
      return FileSlot(
        field: prefix, label: "\(title) file",
        types: pdf ? ConvertUTType.pdf : ConvertUTType.images, allowsMultiple: false,
        help: pdf ? "One PDF used as the mark." : "PNG, JPEG, or WebP.",
        extensions: pdf ? ConvertUTType.pdfExtensions : ConvertUTType.imageExtensions)
    }
  }
#endif
