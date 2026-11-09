#if os(macOS) && arch(arm64)

  import SwiftUI
  import ThistleSupport

  struct FinishingEditor: View {
    @Binding var finishing: ConversionFinishing
    let enabled: Bool

    private let remediateProfiles = [
      "PDF/A-1b", "PDF/A-2b", "PDF/A-3b", "PDF/A-4", "PDF/UA-1", "PDF/UA-2", "Factur-X",
    ]

    var body: some View {
      VStack(alignment: .leading, spacing: 14) {
        Text("After conversion")
          .font(.headline)
          .accessibilityAddTraits(.isHeader)

        Toggle("Merge into one PDF", isOn: $finishing.merge)
          .accessibilityLabel("Merge into one PDF")
        Toggle("Flatten form fields", isOn: $finishing.flattenForm)

        VStack(alignment: .leading, spacing: 8) {
          Text("Split")
            .font(.subheadline.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
          Picker("Split mode", selection: $finishing.splitMode) {
            Text("None").tag("")
            Text("Every N pages").tag("intervals")
            Text("By page ranges").tag("pages")
          }
          .pickerStyle(.menu)
          if finishing.splitMode == "intervals" {
            TextField("Every", text: $finishing.splitEvery, prompt: Text("1"))
              .textFieldStyle(.roundedBorder)
              .accessibilityLabel("Split every number of pages")
          }
          if finishing.splitMode == "pages" {
            TextField("Ranges", text: $finishing.splitRanges, prompt: Text("1-3,5"))
              .textFieldStyle(.roundedBorder)
              .accessibilityLabel("Split page ranges")
          }
        }

        Toggle("Optimize PDF", isOn: $finishing.optimize)

        VStack(alignment: .leading, spacing: 8) {
          Text("Remediate")
            .font(.subheadline.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
          Picker("Profile", selection: profileBinding) {
            Text("None").tag("")
            ForEach(remediateProfiles, id: \.self) { profile in
              Text(profile).tag(profile)
            }
          }
          .pickerStyle(.menu)
          if !finishing.remediate.profiles.isEmpty {
            TextField("Language", text: $finishing.remediate.language, prompt: Text("en"))
              .textFieldStyle(.roundedBorder)
            Toggle("Aggressive", isOn: $finishing.remediate.aggressive)
            TextField("Figure alt text", text: $finishing.remediate.figureAltText)
              .textFieldStyle(.roundedBorder)
          }
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Encryption")
            .font(.subheadline.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
          SecureField("User password", text: $finishing.encrypt.userPassword)
          SecureField("Owner password", text: $finishing.encrypt.ownerPassword)
          Toggle("Allow printing", isOn: $finishing.encrypt.print)
          Toggle("Allow extract text", isOn: $finishing.encrypt.extractText)
          Toggle("Allow modify content", isOn: $finishing.encrypt.modifyContent)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Metadata")
            .font(.subheadline.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
          TextField("Title", text: $finishing.metadata.title).textFieldStyle(.roundedBorder)
          TextField("Author", text: $finishing.metadata.author).textFieldStyle(.roundedBorder)
        }

        if let message = finishing.validationMessage {
          Text(message).font(.caption).foregroundStyle(.red)
        }
      }
      .disabled(!enabled)
    }

    private var profileBinding: Binding<String> {
      Binding(
        get: { finishing.remediate.profiles.first ?? "" },
        set: { newValue in
          finishing.remediate.profiles = newValue.isEmpty ? [] : [newValue]
        })
    }
  }

#endif
