import AppKit
import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// Anything in the app that can be put behind Touch ID.
enum ProtectedScope: String, CaseIterable, Sendable {
    case tray
    case clipboard
    case settings
    case destructive

    var reason: String {
        switch self {
        case .tray: "unlock your file tray"
        case .clipboard: "unlock your clipboard history"
        case .settings: "open Cowly settings"
        case .destructive: "confirm removing these items"
        }
    }

    var title: String {
        switch self {
        case .tray: "Tray locked"
        case .clipboard: "Clipboard locked"
        case .settings: "Settings locked"
        case .destructive: "Confirm"
        }
    }
}

/// Touch ID (and Apple Watch / password fallback) for every gated action.
///
/// A successful check unlocks the scope for `autoLockMinutes`; locking the Mac,
/// sleeping, or letting the timer run out drops every unlocked scope again.
@MainActor
@Observable
final class BiometricGate {
    static let shared = BiometricGate()

    private(set) var unlocked: Set<ProtectedScope> = []
    private(set) var isPrompting = false
    private(set) var lastError: String?
    private var lockTimers: [ProtectedScope: Task<Void, Never>] = [:]

    private init() {
        observeSystemLock()
    }

    // MARK: - Capability

    var availability: Availability {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return .biometrics(context.biometryType)
        }
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            return .passwordOnly
        }
        return .unavailable(error?.localizedDescription ?? "No authentication method available")
    }

    var activeMethodLabel: String { availability.label }
    var activeMethodSymbol: String { availability.symbol }

    enum Availability {
        case biometrics(LABiometryType)
        case passwordOnly
        case unavailable(String)

        var isBiometric: Bool { if case .biometrics = self { return true }; return false }

        var label: String {
            switch self {
            case .biometrics(let type):
                switch type {
                case .touchID: "Touch ID"
                case .opticID: "Optic ID"
                case .faceID: "Face ID"
                default: "Biometrics"
                }
            case .passwordOnly: "Password"
            case .unavailable: "Unavailable"
            }
        }

        var symbol: String {
            switch self {
            case .biometrics(let type):
                switch type {
                case .faceID: "faceid"
                case .opticID: "opticid"
                default: "touchid"
                }
            case .passwordOnly: "key.fill"
            case .unavailable: "lock.slash"
            }
        }
    }

    // MARK: - Policy

    func requiresAuth(for scope: ProtectedScope) -> Bool {
        let prefs = Preferences.shared
        switch scope {
        case .tray: return prefs.lockTray
        case .clipboard: return prefs.lockClipboard
        case .settings: return prefs.lockSettings
        case .destructive: return prefs.confirmDeletesWithBiometrics
        }
    }

    func isUnlocked(_ scope: ProtectedScope) -> Bool {
        !requiresAuth(for: scope) || unlocked.contains(scope)
    }

    // MARK: - Authenticating

    /// Runs `action` only after the scope is unlocked. Returns whether it ran.
    @discardableResult
    func perform(_ scope: ProtectedScope, action: () -> Void) async -> Bool {
        guard await unlock(scope) else { return false }
        action()
        return true
    }

    @discardableResult
    func unlock(_ scope: ProtectedScope) async -> Bool {
        if isUnlocked(scope) { return true }
        return await authenticate(scope)
    }

    /// Always prompts, even if the scope is already unlocked. Used for
    /// destructive confirmations where a fresh touch is the point.
    @discardableResult
    func authenticate(_ scope: ProtectedScope) async -> Bool {
        guard !isPrompting else { return false }
        isPrompting = true
        lastError = nil
        defer { isPrompting = false }
        return await evaluateSystemPolicy(scope)
    }

    private func evaluateSystemPolicy(_ scope: ProtectedScope) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Password…"
        // Each prompt is its own decision; never reuse a system-cached touch.
        context.touchIDAuthenticationAllowableReuseDuration = 0

        let policy: LAPolicy = availability.isBiometric
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        let reason = "Cowly needs to \(scope.reason)."

        do {
            let ok = try await context.evaluatePolicy(policy, localizedReason: reason)
            if ok { markUnlocked(scope) }
            return ok
        } catch let error as LAError where error.code == .userFallback {
            // The user asked for the password sheet explicitly.
            do {
                let ok = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
                if ok { markUnlocked(scope) }
                return ok
            } catch {
                lastError = error.localizedDescription
                return false
            }
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
            return false
        } catch {
            lastError = error.localizedDescription
            log.error("Biometric auth failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Locking

    func lock(_ scope: ProtectedScope) {
        unlocked.remove(scope)
        lockTimers[scope]?.cancel()
        lockTimers[scope] = nil
    }

    func lockAll() {
        for scope in unlocked { lockTimers[scope]?.cancel() }
        lockTimers.removeAll()
        unlocked.removeAll()
    }

    private func markUnlocked(_ scope: ProtectedScope) {
        unlocked.insert(scope)
        Haptics.tap(.levelChange)
        scheduleAutoLock(scope)
    }

    private func scheduleAutoLock(_ scope: ProtectedScope) {
        lockTimers[scope]?.cancel()
        let minutes = Preferences.shared.autoLockMinutes
        guard minutes > 0 else { return }
        lockTimers[scope] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard !Task.isCancelled else { return }
            self?.lock(scope)
        }
    }

    private func observeSystemLock() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            center.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockAll() }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockAll() }
        }
    }
}
