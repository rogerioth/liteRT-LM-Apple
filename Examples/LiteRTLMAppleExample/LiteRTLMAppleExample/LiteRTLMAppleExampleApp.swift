import SwiftUI

@main
struct LiteRTLMAppleExampleApp: App {
    @StateObject private var viewModel = InferenceViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
