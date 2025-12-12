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
    var body: some View {
        if needLoginView && !loggedIn {
            Text("FluxHaus Login")
                .font(Theme.Fonts.headerXL())
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(30)
            VStack {
                if error != nil {
                    Text(error!)
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.error)
                }
                Spacer()
                VStack {
                    SecureField(
                        "Password",
                        text: $viewModel.password
                    )
                    .font(Theme.Fonts.bodyLarge)
                    .padding(.top, 20)
                    Divider()
                        .background(Theme.Colors.textSecondary)
                }
                Spacer()
                Button(action: viewModel.login) {
                    Label("Login", systemImage: "arrow.up")
                        .font(Theme.Fonts.bodyLarge)
                        .foregroundColor(Theme.Colors.accent)
                }
            }
            .padding(30)
            .background(Theme.Colors.background)
            .task {
                checkLogin()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name.loginsUpdated)) { object in
                if (object.userInfo?["loginError"]) != nil {
                    DispatchQueue.main.async {
                        self.error = object.userInfo!["loginError"] as? String
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
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.textPrimary)
        }
    }

    func checkLogin() {
    }
}
