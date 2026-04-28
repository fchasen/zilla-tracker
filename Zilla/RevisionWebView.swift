//
//  RevisionWebView.swift
//  Zilla
//

import SwiftUI
import WebKit

struct RevisionWebView: View {
    @Environment(ViewedRevisionsStore.self) private var viewedRevisions
    let revisionID: Int
    let onClose: () -> Void

    private static let baseURL = URL(string: "https://phabricator.services.mozilla.com")!

    private var revisionURL: URL {
        Self.baseURL.appendingPathComponent("D\(revisionID)")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    onClose()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                .buttonStyle(.borderless)
                .help("Return to bug")

                Text(verbatim: "D\(revisionID)")
                    .font(.callout.weight(.semibold).monospaced())
                    .foregroundStyle(.secondary)

                Spacer()

                Link(destination: revisionURL) {
                    Label("Open in Browser", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open D\(String(revisionID)) in your browser")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            PhabricatorWebView(url: revisionURL)
        }
        .task(id: revisionID) {
            viewedRevisions.markViewed(revisionID)
        }
    }
}

#if os(macOS)
import AppKit

struct PhabricatorWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        context.coordinator.lastURL = url
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastURL != url {
            webView.load(URLRequest(url: url))
            context.coordinator.lastURL = url
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastURL: URL?
    }
}
#else
import UIKit

struct PhabricatorWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        context.coordinator.lastURL = url
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastURL != url {
            webView.load(URLRequest(url: url))
            context.coordinator.lastURL = url
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastURL: URL?
    }
}
#endif
