//
//  SwiftUIView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-09.
//

import SwiftUI

struct LoadingView: View {
    var needLoginView: Bool
    @ObservedObject var viewModel: LoginViewModel = LoginViewModel()

    @State var error: String?
    @State var loggedIn: Bool = false
    @State var isSigningIn: Bool = false
    @State var showDemoLogin: Bool = false
    var body: some View {
        if needLoginView && !loggedIn {
            VStack(spacing: 20) {
                Spacer()
                Text("FluxHaus")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                if let error = error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
                VStack(spacing: 16) {
                    Button(action: signInWithOIDC) {
                        Label("Sign In", systemImage: "person.badge.key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSigningIn)

                    Button(action: { showDemoLogin.toggle() }) {
                        Label(
                            showDemoLogin ? "Hide Demo Mode" : "Demo Mode",
                            systemImage: "play.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if showDemoLogin {
                        SecureField("Demo Passcode", text: $viewModel.password)
                            .textFieldStyle(.roundedBorder)
                        Button(action: {
                            AuthManager.shared.signInDemo(password: viewModel.password)
                            viewModel.login()
                        }) {
                            Label("Enter Demo", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .frame(maxWidth: 360)
                Spacer()
            }
            .padding(30)
            .task {
                checkLogin()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name.loginsUpdated)) { object in
                if (object.userInfo?["loginError"]) != nil {
                    DispatchQueue.main.async {
                        self.error = object.userInfo!["loginError"] as? String
                        self.isSigningIn = false
                    }
                }
                if (object.userInfo?["keysComplete"]) != nil {
                    DispatchQueue.main.async {
                        self.loggedIn = true
                    }
                }
            }
        } else {
            Text("Loading")
        }
    }

    func checkLogin() {
    }

    func signInWithOIDC() {
        isSigningIn = true
        error = nil
        Task {
            do {
                try await AuthManager.shared.signInWithOIDC()
                queryFlux(password: "", user: nil)
            } catch AuthError.cancelled {
                isSigningIn = false
            } catch {
                self.error = error.localizedDescription
                isSigningIn = false
            }
        }
    }
}

#Preview {
    LoadingView(needLoginView: true)
}
