import SwiftUI

@main
struct LiteRTLMAppleExampleApp: App {
    @StateObject private var viewModel = InferenceViewModel()

    init() {
#if DEBUG
        SmokeTestRunner.runIfRequested()
#endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
#if os(macOS)
        .defaultSize(width: 920, height: 760)
#endif
    }
}
