//
//  Login.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-09.
//

import Foundation

@Observable class LoginViewModel {
    var password: String = ""

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
