import SwiftUI

struct EmailNotificationsView: View {
    @EnvironmentObject var appState: AppState
    @State private var gmailAuth = GmailAuthService.shared

    @State private var newName: String = ""
    @State private var newEmail: String = ""
    @State private var showingAddRecipient = false

    var body: some View {
        GroupBox(label: Label("Email Notifications", systemImage: "envelope")) {
            VStack(alignment: .leading, spacing: 16) {

                // MARK: Enable toggle
                Toggle("Send notifications on sync completion", isOn: $appState.emailNotificationSettings.isEnabled)

                Group {

                    Divider()

                    // MARK: Gmail connection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Send From")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let email = gmailAuth.connectedEmail {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(email)
                                    .font(.body)
                                Spacer()
                                Button("Disconnect") {
                                    gmailAuth.signOut()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        } else {
                            HStack {
                                Button {
                                    gmailAuth.signIn()
                                } label: {
                                    Label("Connect Gmail Account", systemImage: "envelope.badge")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(gmailAuth.isConnecting)

                                if gmailAuth.isConnecting {
                                    ProgressView().controlSize(.small)
                                }
                            }
                            if let error = gmailAuth.lastError {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    Divider()

                    // MARK: Notify conditions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notify On")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Success", isOn: $appState.emailNotificationSettings.notifyOnSuccess)
                        Toggle("Failure", isOn: $appState.emailNotificationSettings.notifyOnFailure)
                    }

                    Divider()

                    // MARK: Recipients list
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Recipients")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                showingAddRecipient = true
                            } label: {
                                Label("Add", systemImage: "plus")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if appState.emailNotificationSettings.recipients.isEmpty {
                            Text("No recipients added yet.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(appState.emailNotificationSettings.recipients) { recipient in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(recipient.name)
                                            .font(.body)
                                        Text(recipient.email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        removeRecipient(recipient)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 4)

                                if recipient.id != appState.emailNotificationSettings.recipients.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }

                    Divider()

                    // MARK: Message template
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $appState.emailNotificationSettings.messageTemplate)
                            .font(.body)
                            .frame(minHeight: 80, maxHeight: 160)
                            .scrollContentBackground(.hidden)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                        Text("This message will be included in the notification email sent after each sync.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .disabled(!appState.emailNotificationSettings.isEnabled)
                .opacity(appState.emailNotificationSettings.isEnabled ? 1 : 0.4)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal)
        .sheet(isPresented: $showingAddRecipient) {
            AddRecipientSheet(isPresented: $showingAddRecipient) { name, email in
                let recipient = NotificationRecipient(name: name, email: email)
                appState.emailNotificationSettings.recipients.append(recipient)
            }
        }
    }

    private func removeRecipient(_ recipient: NotificationRecipient) {
        appState.emailNotificationSettings.recipients.removeAll { $0.id == recipient.id }
    }
}

// MARK: - Add Recipient Sheet

struct AddRecipientSheet: View {
    @Binding var isPresented: Bool
    var onAdd: (String, String) -> Void

    @State private var name: String = ""
    @State private var email: String = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@") &&
        email.contains(".")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Recipient")
                .font(.title3)
                .bold()

            Form {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .autocorrectionDisabled()

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
            }
            .formStyle(.columns)

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Button("Add") {
                    onAdd(name.trimmingCharacters(in: .whitespaces), email.trimmingCharacters(in: .whitespaces))
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
