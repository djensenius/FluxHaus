//
//  Login.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-09.
//

import Foundation

class LoginViewModel: ObservableObject {
    @Published var password: String = ""

    func login() {
        LoginAction(
            parameters: LoginRequest(
                password: password
            )
        ).call()
    }

    func loginWithOIDC() {
        Task {
            do {
                try await OIDCManager.shared.login()
                guard let accessToken = OIDCManager.shared.getAccessToken() else {
                    await postLoginError("Failed to retrieve access token")
                    return
                }
                await MainActor.run {
                    queryFluxWithBearer(accessToken: accessToken)
                }
            } catch OIDCError.userCancelled {
                // User cancelled — no error message needed
            } catch {
                await postLoginError(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func postLoginError(_ message: String) {
        NotificationCenter.default.post(
            name: Notification.Name.loginsUpdated,
            object: nil,
            userInfo: ["loginError": message]
        )
    }
}

struct LoginAction {
    var parameters: LoginRequest

    func call() {
        queryFlux(password: parameters.password, user: nil)
    }
}
