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
        let status = (response as? HTTPURLResponse)?.statusCode

        guard let status, (200...299).contains(status) else {
            throw SendError.requestFailed(Self.errorMessage(from: data, status: status))
        }
    }

    /// Pulls the human-readable message out of Gmail's `{"error": {"message": ...}}`
    /// body, falling back to the raw body (or status code) if it isn't shaped that way.
    private static func errorMessage(from data: Data, status: Int?) -> String {
        struct APIError: Decodable { struct Body: Decodable { let message: String }; let error: Body }
        if let decoded = try? JSONDecoder().decode(APIError.self, from: data) {
            return decoded.error.message
        }
        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return raw
        }
        return "HTTP \(status.map(String.init) ?? "error")"
    }

    /// Sends one email per recipient, returning the recipient/reason pairs that failed.
    static func sendIndividually(to recipients: [String], subject: String, body: String) async -> [(recipient: String, reason: String)] {
        var failed: [(recipient: String, reason: String)] = []
        for recipient in recipients {
            do {
                try await send(to: [recipient], subject: subject, body: body)
            } catch {
                failed.append((recipient, describe(error)))
            }
        }
        return failed
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case SendError.notConnected:
            return "Gmail account not connected"
        case SendError.requestFailed(let message):
            return message
        default:
            return error.localizedDescription
        }
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
