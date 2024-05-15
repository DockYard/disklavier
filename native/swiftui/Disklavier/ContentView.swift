//
//  ContentView.swift
//  Disklavier
//

import SwiftUI
import LiveViewNative
import LiveViewNativeLiveForm
import LiveViewNativeAVKit

struct ContentView: View {
    var body: some View {
        #LiveView(
            .automatic(
                development: .localhost(path: "/"),
                production: URL(string: "https://example.com")!
            ),
            addons: [
                LiveFormRegistry<_>.self,
                AVKitRegistry<_>.self
            ]
        ) {
            ConnectingView()
        } disconnected: {
            DisconnectedView()
        } reconnecting: { content, isReconnecting in
            ReconnectingView(isReconnecting: isReconnecting) {
                content
            }
        } error: { error in
            ErrorView(error: error)
        }
    }
}
