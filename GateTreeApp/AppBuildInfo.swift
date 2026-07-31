// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import SwiftUI

enum AppBuildInfo {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"

    static var windowTitle: String {
        #if DEBUG
        return "GateTree - v\(version) - Local build \(buildTimestamp)"
        #else
        return "GateTree - v\(version)"
        #endif
    }

    private static var buildTimestamp: String {
        let buildArtifact = Bundle.main.executableURL ?? Bundle.main.bundleURL
        let buildDate = (try? buildArtifact.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: buildDate)
    }
}

struct WindowTitleSetter: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> TitleView {
        let view = TitleView()
        view.title = title
        return view
    }

    func updateNSView(_ nsView: TitleView, context: Context) {
        nsView.title = title
        nsView.window?.title = title
    }

    final class TitleView: NSView {
        var title = ""

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.title = self.title
            }
        }
    }
}
