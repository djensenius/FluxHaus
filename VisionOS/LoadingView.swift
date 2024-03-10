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
    
    @State var error: String? = nil
    @State var loggedIn: Bool = false
    var body: some View {
        if needLoginView && !loggedIn {
            Text("FluxHaus Login")
                .font(.title)
                .padding(30)
            VStack {
                if error != nil {
                    Text(error!)
                }
                Spacer()
                VStack {
                    SecureField(
                        "Password",
                        text: $viewModel.password
                    )
                    .padding(.top, 20)
                    Divider()
                }
                Spacer()
                Button(
                    action: viewModel.login,
                    label: {
                        Text("Login")
                            .font(.system(size: 24, weight: .bold, design: .default))
                            .frame(maxWidth: .infinity, maxHeight: 60)
                            .foregroundColor(Color.white)
                            .cornerRadius(10)
                    }
                )
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
 LoadingView(needLoginView: false)
 }
 
