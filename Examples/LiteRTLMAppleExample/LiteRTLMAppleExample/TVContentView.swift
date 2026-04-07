#if os(tvOS)
import SwiftUI

private struct TVPromptPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let prompt: String
}

private enum TVPromptCatalog {
    static let all: [TVPromptPreset] = [
        TVPromptPreset(
            id: "on-device-privacy",
            title: "Privacy",
            summary: "Why local inference matters on a television.",
            prompt: "Explain why on-device LiteRT-LM inference on Apple TV can be useful for privacy, latency, and reliability in three concise bullet points."
        ),
        TVPromptPreset(
            id: "family-media",
            title: "Media Guide",
            summary: "A short family-friendly content recommendation prompt.",
            prompt: "Imagine an Apple TV app that summarizes tonight's viewing options for a family of four. Write a concise on-device assistant response with one comedy, one documentary, and one sci-fi suggestion."
        ),
        TVPromptPreset(
            id: "developer-demo",
            title: "Developer Demo",
            summary: "A prompt that shows developers the packaging path is real.",
            prompt: "Describe how a Swift Package Manager integration that downloads a LiteRT-LM model locally on Apple TV differs from a server-backed integration. Keep it under five sentences."
        ),
    ]
}

struct TVContentView: View {
    @ObservedObject var viewModel: InferenceViewModel
    @State private var draftPrompt = ""
    @FocusState private var promptFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 56) {
                    heroSection
                    statusSection
                    modelSection
                    actionSection
                    promptSection
                    responseSection

                    if let benchmark = viewModel.benchmark {
                        benchmarkSection(benchmark)
                    }
                }
                .padding(.horizontal, 90)
                .padding(.top, 60)
                .padding(.bottom, 120)
                .frame(maxWidth: 1700, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(backgroundGradient.ignoresSafeArea())
        }
        .task {
            viewModel.startIfNeeded()
            if draftPrompt.isEmpty {
                draftPrompt = viewModel.prompt
            }
        }
        .onChange(of: viewModel.prompt) { _, newValue in
            draftPrompt = newValue
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(white: 0.06),
                Color(white: 0.02),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LITE RT • LM")
                .font(.callout.weight(.heavy))
                .tracking(6)
                .foregroundStyle(.tint)

            Text("On-Device Inference for Apple TV")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Download a pinned Gemma model, keep it on-device, and run LiteRT-LM inference from a tvOS-native sample app.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 1100, alignment: .leading)
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        section(title: "Status", systemImage: "waveform.path.ecg") {
            HStack(spacing: 24) {
                statusCard
                    .frame(maxWidth: .infinity, alignment: .leading)

                Link(destination: viewModel.selectedModel.huggingFacePageURL) {
                    HStack(spacing: 14) {
                        Image(systemName: "link.circle.fill")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Model Source")
                                .font(.headline)
                            Text("Open on Hugging Face")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 18)
                    .padding(.horizontal, 28)
                }
                .buttonStyle(.card)
            }
        }
    }

    private var statusCard: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(statusTint.opacity(0.18))
                Image(systemName: statusIcon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(statusTint)
            }
            .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.statusTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(viewModel.statusMessage)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .background(panelBackground)
    }

    // MARK: - Models

    private var modelSection: some View {
        section(title: "Model Library", systemImage: "shippingbox.fill") {
            VStack(spacing: 22) {
                ForEach(ExampleModelCatalog.all) { model in
                    Button {
                        viewModel.selectModel(model)
                    } label: {
                        modelRow(model)
                    }
                    .buttonStyle(.card)
                }
            }
        }
    }

    private func modelRow(_ model: ExampleModelDescriptor) -> some View {
        let isSelected = viewModel.selectedModel == model
        let isLocal = isSelected && viewModel.localModelURL != nil
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(model.displayName)
                    .font(.title2.weight(.semibold))
                Spacer()
                if isSelected {
                    Label("Selected", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Text(model.summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                metaPill("Size", model.sizeDescription)
                metaPill("File", model.fileName, monospaced: true)
                metaPill("Storage", isLocal ? "Local" : "Remote")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private var actionSection: some View {
        section(title: "Actions", systemImage: "sparkles.rectangle.stack.fill") {
            VStack(spacing: 22) {
                if viewModel.isDownloading, let progress = viewModel.downloadProgress {
                    downloadProgressCard(progress)
                }

                HStack(spacing: 22) {
                    actionButton(
                        title: viewModel.isDownloading ? "Downloading…" : "Download Model",
                        systemImage: "arrow.down.circle.fill",
                        tint: .blue,
                        enabled: viewModel.canDownloadSelectedModel
                    ) {
                        viewModel.downloadSelectedModel()
                    }

                    actionButton(
                        title: viewModel.isRunning ? "Running…" : "Run Inference",
                        systemImage: "play.circle.fill",
                        tint: .orange,
                        enabled: viewModel.canRunInference
                    ) {
                        viewModel.runInference()
                    }

                    actionButton(
                        title: "Delete Local",
                        systemImage: "trash.fill",
                        tint: .red,
                        enabled: viewModel.canDeleteSelectedModel
                    ) {
                        viewModel.deleteSelectedModel()
                    }
                }
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .padding(.horizontal, 24)
        }
        .buttonStyle(.card)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.45)
    }

    private func downloadProgressCard(_ progress: ModelDownloadProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Downloading")
                    .font(.headline)
                Spacer()
                Text(progress.percentDescription)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress.fractionCompleted)
                .tint(.blue)
            Text("\(progress.completedDescription) of \(progress.totalDescription)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground)
    }

    // MARK: - Prompt

    private var promptSection: some View {
        section(title: "Prompt Studio", systemImage: "text.bubble.fill") {
            VStack(alignment: .leading, spacing: 24) {
                Text("Choose a curated preset or open the editor to type with the on-screen keyboard.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Button {
                    promptFieldFocused = true
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.pencil")
                            Text("Active Prompt")
                                .font(.headline)
                            Spacer()
                            Text("Tap to edit")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(draftPrompt.isEmpty ? "No prompt set." : draftPrompt)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(6)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.card)

                // Hidden field that the focus state above brings up the keyboard for.
                TextField("Edit prompt", text: $draftPrompt, axis: .vertical)
                    .focused($promptFieldFocused)
                    .opacity(0)
                    .frame(height: 1)
                    .accessibilityHidden(true)

                HStack(spacing: 22) {
                    Button {
                        viewModel.setPrompt(draftPrompt, source: "tvOS editor")
                    } label: {
                        Label("Apply Prompt", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .padding(.vertical, 22)
                            .padding(.horizontal, 32)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.card)
                    .disabled(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftPrompt == viewModel.prompt)

                    Button {
                        draftPrompt = viewModel.prompt
                    } label: {
                        Label("Revert", systemImage: "arrow.uturn.backward")
                            .font(.headline)
                            .padding(.vertical, 22)
                            .padding(.horizontal, 32)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.card)
                    .disabled(draftPrompt == viewModel.prompt)
                }

                Text("PRESETS")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 28) {
                        ForEach(TVPromptCatalog.all) { preset in
                            Button {
                                draftPrompt = preset.prompt
                                viewModel.setPrompt(preset.prompt, source: "tvOS preset \(preset.id)")
                            } label: {
                                presetCard(preset)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.vertical, 30)
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    private func presetCard(_ preset: TVPromptPreset) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(preset.title)
                .font(.title3.weight(.bold))
            Text(preset.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(preset.prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(5)
        }
        .padding(26)
        .frame(width: 360, height: 280, alignment: .topLeading)
    }

    // MARK: - Response

    private var responseSection: some View {
        section(title: "Response", systemImage: "waveform.and.magnifyingglass") {
            VStack(alignment: .leading, spacing: 20) {
                if !viewModel.errorMessage.isEmpty {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        Text(viewModel.errorMessage)
                            .font(.body)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                Button {} label: {
                    Group {
                        if viewModel.isRunning {
                            HStack(spacing: 16) {
                                ProgressView()
                                Text("Generating on Apple TV…")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        } else if viewModel.response.isEmpty {
                            Text("No response yet. Download a model, choose a prompt, and run on-device inference.")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(viewModel.response)
                                .font(.title3)
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                }
                .buttonStyle(.card)
            }
        }
    }

    // MARK: - Benchmark

    private func benchmarkSection(_ benchmark: InferenceBenchmark) -> some View {
        section(title: "Benchmark", systemImage: "speedometer") {
            HStack(spacing: 28) {
                metricCard(title: "Initialization", value: benchmark.initializationDescription)
                metricCard(title: "Time To First Token", value: benchmark.timeToFirstTokenDescription)
            }
        }
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.0)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(panelBackground)
    }

    // MARK: - Helpers

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10))
            )
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(title.uppercased())
                    .font(.subheadline.weight(.heavy))
                    .tracking(2.4)
                    .foregroundStyle(.white.opacity(0.85))
            }
            content()
        }
    }

    private func metaPill(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var statusTint: Color {
        if !viewModel.errorMessage.isEmpty { return .red }
        if viewModel.isRunning || viewModel.isDownloading { return .orange }
        if viewModel.localModelURL != nil { return .green }
        return .blue
    }

    private var statusIcon: String {
        if !viewModel.errorMessage.isEmpty { return "exclamationmark.triangle.fill" }
        if viewModel.isRunning { return "sparkles" }
        if viewModel.isDownloading { return "arrow.down.circle.fill" }
        if viewModel.localModelURL != nil { return "checkmark.circle.fill" }
        return "circle.dotted"
    }
}

#Preview {
    TVContentView(viewModel: InferenceViewModel())
}
#endif
