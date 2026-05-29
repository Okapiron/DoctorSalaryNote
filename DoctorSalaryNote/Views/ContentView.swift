import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var appSettings: [AppSettings]
    @AppStorage("biometricLockEnabled") private var storedBiometricLockEnabled = false

    @State private var isUnlocked = false
    @State private var authenticationMessage: String?

    private var isBiometricLockEnabled: Bool {
        appSettings.first?.isBiometricLockEnabled ?? storedBiometricLockEnabled
    }

    var body: some View {
        ZStack {
            mainTabs

            if isBiometricLockEnabled && !isUnlocked {
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
                if !isUnlocked {
                    authenticate()
                }
            } else if newPhase == .inactive || newPhase == .background {
                isUnlocked = false
                authenticationMessage = nil
            }
        }
        .onChange(of: isBiometricLockEnabled) { _, isEnabled in
            storedBiometricLockEnabled = isEnabled
            if isEnabled {
                isUnlocked = false
                authenticate()
            } else {
                isUnlocked = true
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
                    authenticationMessage = nil
                }
            } catch {
                await MainActor.run {
                    isUnlocked = false
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
