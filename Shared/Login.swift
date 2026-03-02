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
}

struct LoginAction {
    var parameters: LoginRequest

    func call() {
        queryFlux(password: parameters.password)
    }
}
