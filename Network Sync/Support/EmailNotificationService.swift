import Foundation
import AppKit

struct EmailNotificationService {

    /// Called after a sync completes. Opens a pre-filled mailto: draft
    /// for each recipient in the notification settings.
    static func sendSyncComplete(converted: Int, errors: Int) {
        let settings = AppState.shared.emailNotificationSettings
        guard settings.isEnabled else { return }
        guard !settings.recipients.isEmpty else { return }

        let success = errors == 0
        if success && !settings.notifyOnSuccess { return }
        if !success && !settings.notifyOnFailure { return }

        let subject = success
            ? "✅ Sync Complete — \(converted) file\(converted == 1 ? "" : "s") converted"
            : "⚠️ Sync Complete with Errors — \(errors) error\(errors == 1 ? "" : "s")"

        let body = buildBody(converted: converted, errors: errors, settings: settings)

        for recipient in settings.recipients {
            openMailto(to: recipient.email, subject: subject, body: body)
        }
    }

    // MARK: - Private

    private static func buildBody(
        converted: Int,
        errors: Int,
        settings: EmailNotificationSettings
    ) -> String {
        let dateLine = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)
        var lines: [String] = []
        lines.append("Network Sync Report — \(dateLine)")
        lines.append("")
        lines.append("Files converted: \(converted)")
        lines.append("Errors: \(errors)")
        lines.append("")
        if !settings.messageTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(settings.messageTemplate)
            lines.append("")
        }
        lines.append("—")
        lines.append("Sent by Network Sync")
        return lines.joined(separator: "\n")
    }

    private static func openMailto(to: String, subject: String, body: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
