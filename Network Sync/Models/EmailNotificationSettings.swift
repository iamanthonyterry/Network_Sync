import Foundation

struct NotificationRecipient: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var email: String
}

struct EmailNotificationSettings: Codable {
    var recipients: [NotificationRecipient] = []
    var messageTemplate: String = "The sync has completed successfully. Please review the attached summary."
    var isEnabled: Bool = true
    var notifyOnSuccess: Bool = true
    var notifyOnFailure: Bool = true
}
