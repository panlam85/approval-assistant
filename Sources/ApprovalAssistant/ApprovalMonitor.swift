import Combine
import Foundation
import ServiceManagement

@MainActor
final class ApprovalMonitor: ObservableObject {
    private static let legacyDefaultsDomain = "com.tiktaknto.codex-approval-assistant"

    private enum DefaultsKey {
        static let isEnabled = "isEnabled"
        static let approvalChoice = "approvalChoice"
    }

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: DefaultsKey.isEnabled)
            if isEnabled {
                lastEvent = "Monitoring Terminal for Codex approval prompts…"
                checkNow(allowAction: true)
            } else {
                lastEvent = "Automatic approval is paused."
            }
        }
    }

    @Published var approvalChoiceRawValue: Int {
        didSet {
            defaults.set(approvalChoiceRawValue, forKey: DefaultsKey.approvalChoice)
        }
    }

    @Published private(set) var isScanning = false
    @Published private(set) var lastEvent = "Automatic approval is paused."
    @Published private(set) var lastApprovalTTY: String?
    @Published private(set) var launchAtLoginEnabled = false

    private let defaults: UserDefaults
    private let terminalAutomation: TerminalAutomation
    private var promptLatch = PromptLatch()
    private var monitorTask: Task<Void, Never>?

    var approvalChoice: ApprovalChoice {
        ApprovalChoice(rawValue: approvalChoiceRawValue) ?? .approveOnce
    }

    init(
        defaults: UserDefaults = .standard,
        terminalAutomation: TerminalAutomation = TerminalAutomation()
    ) {
        self.defaults = defaults
        self.terminalAutomation = terminalAutomation

        let legacyDefaults = UserDefaults(suiteName: Self.legacyDefaultsDomain)
        let hasCurrentEnabledValue = defaults.object(forKey: DefaultsKey.isEnabled) != nil
        let hasLegacyEnabledValue = legacyDefaults?.object(forKey: DefaultsKey.isEnabled) != nil
        let migratedLegacySettings = !hasCurrentEnabledValue && hasLegacyEnabledValue

        self.isEnabled = hasCurrentEnabledValue
            ? defaults.bool(forKey: DefaultsKey.isEnabled)
            : legacyDefaults?.bool(forKey: DefaultsKey.isEnabled) ?? false

        let savedChoice = defaults.object(forKey: DefaultsKey.approvalChoice) != nil
            ? defaults.integer(forKey: DefaultsKey.approvalChoice)
            : legacyDefaults?.integer(forKey: DefaultsKey.approvalChoice)
                ?? ApprovalChoice.approveOnce.rawValue
        self.approvalChoiceRawValue = ApprovalChoice(rawValue: savedChoice)?.rawValue
            ?? ApprovalChoice.approveOnce.rawValue
        self.launchAtLoginEnabled = SMAppService.mainApp.status == .enabled

        if migratedLegacySettings {
            defaults.set(isEnabled, forKey: DefaultsKey.isEnabled)
            defaults.set(approvalChoiceRawValue, forKey: DefaultsKey.approvalChoice)
        }

        startMonitoring()
    }

    deinit {
        monitorTask?.cancel()
    }

    func probeNow() {
        checkNow(allowAction: false)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            lastEvent = launchAtLoginEnabled
                ? "The assistant will open when you log in."
                : "Launch at login is off."
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            lastEvent = "Launch-at-login change failed: \(error.localizedDescription)"
        }
    }

    func openAutomationSettings() {
        terminalAutomation.openAutomationSettings()
    }

    private func startMonitoring() {
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if self?.isEnabled == true {
                    self?.checkNow(allowAction: true)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func checkNow(allowAction: Bool) {
        guard !isScanning else {
            return
        }
        isScanning = true
        defer { isScanning = false }

        do {
            let snapshots = try terminalAutomation.scanTabs()
            var activePromptTTYs = Set<String>()
            var detectedPromptCount = 0

            for snapshot in snapshots where snapshot.containsCodexProcess {
                guard let prompt = PromptMatcher.match(contents: snapshot.contents) else {
                    continue
                }

                detectedPromptCount += 1
                activePromptTTYs.insert(snapshot.tty)

                guard allowAction, isEnabled, promptLatch.shouldHandle(tty: snapshot.tty, prompt: prompt) else {
                    continue
                }

                let responseNumber = prompt.responseNumber(for: approvalChoice)
                let result = try terminalAutomation.answer(
                    snapshot: snapshot,
                    expectedPrompt: prompt,
                    responseNumber: responseNumber
                )

                if result == .sent {
                    promptLatch.markHandled(tty: snapshot.tty, prompt: prompt)
                    lastApprovalTTY = snapshot.tty
                    if approvalChoice == .approveAndRemember, !prompt.supportsRemember {
                        lastEvent = "Sent 1 to Codex in \(snapshot.tty); remember was unavailable."
                    } else {
                        lastEvent = "Sent \(responseNumber) to Codex in \(snapshot.tty)."
                    }
                } else if result != .promptGone {
                    lastEvent = "Skipped \(snapshot.tty): \(result.rawValue.replacingOccurrences(of: "_", with: " "))."
                }
            }

            promptLatch.reconcile(activePromptTTYs: activePromptTTYs)

            if !allowAction {
                lastEvent = detectedPromptCount == 0
                    ? "No current Codex approval prompt found."
                    : "Found \(detectedPromptCount) Codex approval prompt\(detectedPromptCount == 1 ? "" : "s"); no key was sent."
            } else if detectedPromptCount == 0, lastApprovalTTY == nil {
                lastEvent = "Monitoring Terminal; no approval prompt is waiting."
            }
        } catch let error as TerminalAutomationError {
            if error.code == -1_743 {
                isEnabled = false
                lastEvent = error.localizedDescription
            } else {
                lastEvent = "Scan skipped; retrying automatically. \(error.localizedDescription)"
            }
        } catch {
            lastEvent = "Scan skipped; retrying automatically. \(error.localizedDescription)"
        }
    }
}
