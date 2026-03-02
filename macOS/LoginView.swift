//
//  LoginView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI

struct LoginView: View {
    var needLoginView: Bool
    @State private var password = ""
    @State private var isLoading = false
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
                isLoading = false
            }
        }
    }

    private var loginCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "house.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.accent)

            Text("FluxHaus")
                .font(Theme.Fonts.header4XL())
                .foregroundColor(Theme.Colors.textPrimary)

            if let error = errorMessage {
                Text(error)
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.error)
            }

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .onSubmit { signIn() }

            Button(action: signIn) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Sign In")
                }
            }
            .buttonStyle(.glass)
            .disabled(password.isEmpty || isLoading)
            .frame(width: 250)

            Divider()
                .frame(width: 200)

            Button(action: signInWithOIDC, label: {
                Label("Sign in with SSO", systemImage: "person.badge.key")
            })
            .buttonStyle(.glass)
            .frame(width: 250)
        }
        .padding(40)
        .glassEffect(.regular)
        .frame(width: 350)
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
        .glassEffect(.regular)
    }

    private func signIn() {
        isLoading = true
        errorMessage = nil
        AuthManager.shared.signInDemo(password: password)
        queryFlux(password: password)
    }

    private func signInWithOIDC() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await AuthManager.shared.signInWithOIDC()
                queryFlux(password: "")
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
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
