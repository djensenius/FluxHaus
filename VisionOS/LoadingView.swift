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
                    SecureField("Password", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)
                    Button(action: viewModel.login) {
                        Label("Login", systemImage: "arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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
}

#Preview {
    LoadingView(needLoginView: true)
}
