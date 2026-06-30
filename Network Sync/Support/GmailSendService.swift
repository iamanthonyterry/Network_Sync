import Foundation

/// Sends email via the Gmail API using the signed-in user's access token.
enum GmailSendService {

    enum SendError: Error {
        case notConnected
        case requestFailed(String)
    }

    static func send(to recipients: [String], subject: String, body: String) async throws {
        guard let accessToken = await GmailAuthService.shared.validAccessToken() else {
            throw SendError.notConnected
        }

        let raw = buildRawMessage(to: recipients, subject: subject, body: body)
        let base64URL = raw
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["raw": base64URL])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SendError.requestFailed(message)
        }
    }

    /// Sends one email per recipient, returning the recipients that failed.
    static func sendIndividually(to recipients: [String], subject: String, body: String) async -> [String] {
        var failed: [String] = []
        for recipient in recipients {
            do {
                try await send(to: [recipient], subject: subject, body: body)
            } catch {
                failed.append(recipient)
            }
        }
        return failed
    }

    private static func buildRawMessage(to recipients: [String], subject: String, body: String) -> Data {
        let message = """
        To: \(recipients.joined(separator: ", "))
        Subject: \(subject)
        Content-Type: text/plain; charset="UTF-8"

        \(body)
        """
        return Data(message.utf8)
    }
}
