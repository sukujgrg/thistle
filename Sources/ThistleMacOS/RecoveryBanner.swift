#if os(macOS) && arch(arm64)

  import AppKit
  import SwiftUI

  /// Bottom recovery bar for engine failures: plain title, selectable detail, primary + Details.
  struct RecoveryBanner: View {
    let title: String
    let detail: String
    let primaryTitle: String
    let showsDetails: Bool
    var onPrimary: () -> Void
    var onDetails: (() -> Void)?

    var body: some View {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
          .accessibilityHidden(true)
          .padding(.top, 2)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.callout.weight(.semibold))
          Text(detail)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Engine recovery")
        .accessibilityValue("\(title). \(detail)")

        HStack(spacing: 8) {
          Button(primaryTitle, action: onPrimary)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel(primaryTitle)
          if showsDetails, let onDetails {
            Button("Details", action: onDetails)
              .buttonStyle(.bordered)
              .controlSize(.small)
              .accessibilityLabel("Details")
              .accessibilityHint("Shows the engine inspector and activity log")
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(.red.opacity(0.08))
      .accessibilityElement(children: .contain)
    }
  }

  /// Inline failure used by action run / import / save — same language pattern as RecoveryBanner.
  struct InlineFailure: View {
    let title: String
    let detail: String
    var copyLabel: String = "Copy error"
    var showsCopy: Bool = true

    var body: some View {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.circle.fill")
          .foregroundStyle(.red)
          .accessibilityHidden(true)
          .padding(.top, 1)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.callout.weight(.semibold))
          Text(detail)
            .font(.callout)
            .foregroundStyle(.red.opacity(0.9))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(detail)

        if showsCopy {
          Button(copyLabel) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(detail, forType: .string)
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
          .accessibilityLabel(copyLabel)
        }
      }
      .padding(10)
      .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

#endif
