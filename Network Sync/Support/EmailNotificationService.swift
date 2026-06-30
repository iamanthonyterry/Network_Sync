import Foundation

/// Sends sync-completion notification emails via the connected Gmail account.
struct EmailNotificationService {

    static func sendSyncComplete(converted: Int, errors: Int) async {
        let settings = AppState.shared.emailNotificationSettings
        guard settings.isEnabled else { return }
        guard !settings.recipients.isEmpty else { return }
        guard await GmailAuthService.shared.isConnected else { return }

        let success = errors == 0
        if success && !settings.notifyOnSuccess { return }
        if !success && !settings.notifyOnFailure { return }

        let subject = success
            ? "✅ Sync Complete — \(converted) file\(converted == 1 ? "" : "s") converted"
            : "⚠️ Sync Complete with Errors — \(errors) error\(errors == 1 ? "" : "s")"

        let body = buildBody(converted: converted, errors: errors, settings: settings)
        let addresses = settings.recipients.map(\.email)

        let failed = await GmailSendService.sendIndividually(to: addresses, subject: subject, body: body)
        if !failed.isEmpty {
            await MainActor.run {
                AppState.shared.log("⚠️ Failed to email: \(failed.joined(separator: ", "))")
            }
        }
    }

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
}
