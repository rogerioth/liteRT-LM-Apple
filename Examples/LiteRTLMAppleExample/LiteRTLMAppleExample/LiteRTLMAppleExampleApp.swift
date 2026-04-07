import SwiftUI

@main
struct LiteRTLMAppleExampleApp: App {
    @StateObject private var viewModel = InferenceViewModel()

    var body: some Scene {
        WindowGroup {
#if os(tvOS)
            TVContentView(viewModel: viewModel)
#else
            ContentView(viewModel: viewModel)
#endif
        }
#if os(macOS)
        .defaultSize(width: 920, height: 760)
#endif
    }
}
