import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var appSettings: [AppSettings]
    @AppStorage("biometricLockEnabled") private var storedBiometricLockEnabled = false

    @State private var isUnlocked = false
    @State private var isPrivacyCovered = false
    @State private var authenticationMessage: String?
    @State private var backgroundEnteredAt: Date?

    private let biometricLockDelay: TimeInterval = 60

    private var isBiometricLockEnabled: Bool {
        appSettings.first?.isBiometricLockEnabled ?? storedBiometricLockEnabled
    }

    private var shouldShowLockedContent: Bool {
        isBiometricLockEnabled && (!isUnlocked || isPrivacyCovered)
    }

    var body: some View {
        ZStack {
            mainTabs

            if shouldShowLockedContent {
                LockedContentView(
                    message: authenticationMessage,
                    authenticateAction: authenticate
                )
            }
        }
        .onAppear {
            storedBiometricLockEnabled = isBiometricLockEnabled
            if isBiometricLockEnabled {
                authenticate()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard isBiometricLockEnabled else {
                return
            }

            if newPhase == .active {
                let elapsed = backgroundEnteredAt.map { Date().timeIntervalSince($0) } ?? biometricLockDelay
                backgroundEnteredAt = nil

                if elapsed >= biometricLockDelay {
                    isPrivacyCovered = false
                    isUnlocked = false
                    authenticate()
                } else {
                    isPrivacyCovered = false
                }
            } else if newPhase == .inactive || newPhase == .background {
                backgroundEnteredAt = Date()
                isPrivacyCovered = true
                authenticationMessage = nil
            }
        }
        .onChange(of: isBiometricLockEnabled) { _, isEnabled in
            storedBiometricLockEnabled = isEnabled
            if isEnabled {
                isUnlocked = true
                isPrivacyCovered = false
                backgroundEnteredAt = nil
                authenticationMessage = nil
            } else {
                isUnlocked = true
                isPrivacyCovered = false
                backgroundEnteredAt = nil
                authenticationMessage = nil
            }
        }
    }

    private var mainTabs: some View {
        TabView {
            NavigationStack {
                HomeSummaryView()
            }
            .tabItem {
                Label("ホーム", systemImage: "house")
            }

            PayRecordListView()
                .tabItem {
                    Label("給与", systemImage: "list.bullet.rectangle")
                }

            NavigationStack {
                DocumentListView()
            }
            .tabItem {
                Label("書類", systemImage: "doc.text")
            }

            NavigationStack {
                AnalysisView()
            }
            .tabItem {
                Label("分析", systemImage: "chart.bar")
            }
        }
        .tint(.teal)
    }

    private func authenticate() {
        authenticationMessage = nil

        if let unavailableMessage = BiometricAuthenticator.unavailableMessage() {
            isUnlocked = false
            authenticationMessage = unavailableMessage
            return
        }

        Task {
            do {
                try await BiometricAuthenticator.authenticate(reason: "医師給与ノートの内容を表示するため認証してください。")
                await MainActor.run {
                    isUnlocked = true
                    isPrivacyCovered = false
                    authenticationMessage = nil
                }
            } catch {
                await MainActor.run {
                    isUnlocked = false
                    isPrivacyCovered = false
                    authenticationMessage = "認証できませんでした。給与情報を表示するには再度認証してください。"
                }
            }
        }
    }
}

private struct LockedContentView: View {
    let message: String?
    let authenticateAction: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("医師給与ノートはロックされています")
                    .font(.headline)
                Text(message ?? "給与情報を表示するには認証してください。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: authenticateAction) {
                Label("認証する", systemImage: "faceid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

#Preview {
    ContentView()
}
