//
//  WeatherAlertView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-27.
//

import SwiftUI
import WeatherKit
import WebKit

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

#if os(macOS)
struct AlertWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#else
struct AlertWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#endif

struct WeatherAlertView: View {
    @Environment(\.dismiss) var dismiss
    var alerts: [WeatherAlert]
    @State private var selectedAlert: WeatherAlert?

    var body: some View {
        NavigationStack {
            Group {
                if let alert = selectedAlert {
                    AlertWebView(url: alert.detailsURL)
                        .ignoresSafeArea(.container, edges: .bottom)
                        .navigationTitle(alert.summary)
                        #if !os(macOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            #if !os(macOS)
                            ToolbarItem(placement: .topBarLeading) {
                                if alerts.count > 1 {
                                    Button("Back") { selectedAlert = nil }
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { dismiss() }
                            }
                            #else
                            ToolbarItem(placement: .cancellationAction) {
                                if alerts.count > 1 {
                                    Button("Back") { selectedAlert = nil }
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { dismiss() }
                            }
                            #endif
                        }
                } else {
                    alertList
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
        .onAppear {
            if alerts.count == 1 {
                selectedAlert = alerts.first
            }
        }
    }

    private var alertList: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Weather Alerts")
                    .font(Theme.Fonts.headerLarge())
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.top)
                ForEach(alerts, id: \.summary) { alert in
                    Button {
                        selectedAlert = alert
                    } label: {
                        alertRow(alert: alert)
                    }
                }
            }
            .padding(.horizontal)
        }
        .toolbar {
            #if !os(macOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
            #else
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
            #endif
        }
        #if !os(visionOS)
        .background(Theme.Colors.background)
        #endif
    }

    private func alertRow(alert: WeatherAlert) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let region = alert.region {
                Text("\(alert.severity.description.capitalized) alert for \(region)")
                    .font(Theme.Fonts.bodyLarge)
                    .foregroundColor(Theme.Colors.error)
            } else {
                Text(alert.severity.description.capitalized)
                    .font(Theme.Fonts.bodyLarge)
                    .foregroundColor(Theme.Colors.error)
            }
            Text(alert.summary)
                .font(Theme.Fonts.bodyMedium)
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.leading)
            Text("Source: \(alert.source)")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        #if !os(visionOS)
        .background(Theme.Colors.secondaryBackground)
        #endif
        .cornerRadius(12)
    }
}
