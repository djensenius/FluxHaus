//
//  LoginView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI

struct LoginView: View {
    var needLoginView: Bool
    @ObservedObject var viewModel: LoginViewModel = LoginViewModel()
    @State private var isSigningIn = false
    @State private var showDemoLogin = false
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            Spacer()
            if needLoginView {
                loginCard
            } else {
                loadingCard
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name.loginsUpdated
            )
        ) { object in
            if let error = object.userInfo?["loginError"] as? String {
                errorMessage = error
                isSigningIn = false
            }
        }
    }

    private var loginCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "house.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.accent)

            Text("FluxHaus")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(Theme.Colors.textPrimary)

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(Theme.Colors.error)
                    .font(Theme.Fonts.bodySmall)
            }

            VStack(spacing: 12) {
                Button(action: signInWithOIDC) {
                    Label("Sign In", systemImage: "person.badge.key")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSigningIn)

                Button(action: { showDemoLogin.toggle() }, label: {
                    Label(
                        showDemoLogin ? "Hide Demo Mode" : "Demo Mode",
                        systemImage: "play.circle"
                    )
                    .frame(maxWidth: .infinity)
                })
                .buttonStyle(.bordered)
                .controlSize(.large)

                if showDemoLogin {
                    SecureField("Demo Passcode", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { signInDemo() }

                    Button(action: signInDemo, label: {
                        Label("Enter Demo", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    })
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(viewModel.password.isEmpty)
                }
            }
            .frame(width: 280)
        }
        .padding(40)
        .frame(width: 380)
    }

    private var loadingCard: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Connecting…")
                .font(Theme.Fonts.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(40)
    }

    private func signInDemo() {
        isSigningIn = true
        errorMessage = nil
        AuthManager.shared.signInDemo(password: viewModel.password)
        viewModel.login()
    }

    private func signInWithOIDC() {
        isSigningIn = true
        errorMessage = nil
        Task {
            do {
                try await AuthManager.shared.signInWithOIDC()
                queryFlux(password: "")
            } catch {
                errorMessage = error.localizedDescription
                isSigningIn = false
            }
        }
    }
}

#if DEBUG
#Preview("Login") {
    LoginView(needLoginView: true)
}

#Preview("Loading") {
    LoginView(needLoginView: false)
}
#endif
