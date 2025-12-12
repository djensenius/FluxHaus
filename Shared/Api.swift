//
//  Api.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-08-07.
//

import Foundation

@MainActor
class Api: ObservableObject {
    @Published var response: LoginResponse?

    func setApiResponse(apiResponse: LoginResponse) {
        self.response = apiResponse
    }
}
