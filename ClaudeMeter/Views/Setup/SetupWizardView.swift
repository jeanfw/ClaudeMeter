//
//  SetupWizardView.swift
//  ClaudeMeter
//
//  Created by Edd on 2025-11-14.
//

import SwiftUI
import AppKit

/// Setup wizard view used for the very first account, and for adding additional accounts.
struct SetupWizardView: View {
    @Bindable var appModel: AppModel
    /// Called when the wizard finishes successfully (used to dismiss the popover/sheet).
    var onComplete: (() -> Void)? = nil

    @State private var labelInput: String = ""
    @State private var sessionKeyInput: String = ""
    @State private var isValidating: Bool = false
    @State private var errorMessage: String?
    @State private var hasValidationSucceeded: Bool = false
    @State private var isImporting: Bool = false
    @State private var offersFullDiskAccessSettings: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                if let appIcon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                }

                Text(appModel.settings.accounts.isEmpty ? "Welcome to ClaudeMeter" : "Add Another Account")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Monitor your Claude.ai plan usage in real-time")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 32)

            VStack(alignment: .leading, spacing: 8) {
                Text("Account Label")
                    .font(.headline)

                TextField("e.g. Personal, Client X", text: $labelInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isBusy)
                    .accessibilityLabel("Account label")

                Text("Used to distinguish this account in the menu bar")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 8) {
                Text("Claude Session Key")
                    .font(.headline)

                SecureField("sk-ant-...", text: $sessionKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isBusy)
                    .accessibilityLabel("Session key input field")
                    .accessibilityHint("Enter your Claude session key or paste a Cookie header containing sessionKey")

                Text("Import from a browser signed in to claude.ai, or paste your session")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !sessionKeyInput.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: isFormatValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(isFormatValid ? .green : .red)
                        Text(isFormatValid ? "Format valid" : "Invalid format (must start with sk-ant-)")
                            .font(.caption)
                            .foregroundColor(isFormatValid ? .green : .red)
                    }
                }
            }
            .padding(.horizontal, 32)

            if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .frame(width: 20)
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundColor(.orange)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if offersFullDiskAccessSettings {
                        Button("Open Full Disk Access") {
                            SystemSettingsOpener.openFullDiskAccess()
                        }
                        .controlSize(.small)
                        .padding(.leading, 28)
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 32)
                .accessibilityLabel("Error: \(errorMessage)")
            }

            if hasValidationSucceeded {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Account added!")
                        .font(.callout)
                        .foregroundColor(.green)
                }
                .padding(12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 8) {
                Button(action: {
                    Task { await importAndSave() }
                }) {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isImporting ? "Importing..." : "Import from Browser")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
                .accessibilityLabel(isImporting ? "Importing session key" : "Import session key from browser")
                .accessibilityHint("Finds your Claude session key in local browser cookies and adds the account")

                Button(action: {
                    Task { await validateAndSave() }
                }) {
                    HStack {
                        Text(isValidating ? "Validating..." : "Continue Manually")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(!isFormatValid || isBusy)
                .accessibilityLabel(isValidating ? "Validating session key" : "Continue with manual setup")
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .frame(width: 370, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Validation

    private var isBusy: Bool {
        isValidating || isImporting
    }

    private var isFormatValid: Bool {
        let trimmed = sessionKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = SessionKey.extractSessionKeyValue(from: trimmed) else { return false }
        return value.hasPrefix("sk-ant-") && value.count > 10
    }

    /// Import the session key from browser cookies, then add the account with it.
    @MainActor
    private func importAndSave() async {
        isImporting = true
        errorMessage = nil
        offersFullDiskAccessSettings = false
        hasValidationSucceeded = false

        do {
            let imported = try await appModel.importSessionKeyFromBrowser()
            sessionKeyInput = imported.value
            isImporting = false
            await validateAndSave()
            return
        } catch let error as SessionKeyImportError {
            errorMessage = error.localizedDescription
            offersFullDiskAccessSettings = error.offersFullDiskAccessSettings
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }

        isImporting = false
    }

    @MainActor
    private func validateAndSave() async {
        guard !sessionKeyInput.isEmpty else {
            errorMessage = "Session key cannot be empty"
            hasValidationSucceeded = false
            return
        }

        isValidating = true
        errorMessage = nil
        offersFullDiskAccessSettings = false
        hasValidationSucceeded = false

        do {
            let resolvedLabel = labelInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let account = try await appModel.addAccount(label: resolvedLabel, sessionKey: sessionKeyInput)
            if account != nil {
                hasValidationSucceeded = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    onComplete?()
                }
            } else {
                errorMessage = "Session key is invalid or expired"
            }
        } catch let error as SessionKeyError {
            errorMessage = error.localizedDescription
        } catch let error as NetworkError {
            errorMessage = "Network error: \(error.localizedDescription)"
        } catch let error as AppError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Validation failed: \(error.localizedDescription)"
        }

        isValidating = false
    }
}
