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

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.12, blue: 0.20),
                        Color(red: 0.04, green: 0.05, blue: 0.10),
                        Color.black,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        heroPanel

                        HStack(alignment: .top, spacing: 28) {
                            modelPanel
                            actionPanel
                        }

                        promptPanel
                        responsePanel

                        if let benchmark = viewModel.benchmark {
                            benchmarkPanel(benchmark)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 48)
                    .frame(maxWidth: 1500, alignment: .leading)
                }
            }
            .navigationTitle("LiteRT-LM")
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

    private var heroPanel: some View {
        TVPanel {
            VStack(alignment: .leading, spacing: 16) {
                Text("Apple TV Demo")
                    .font(.system(size: 48, weight: .bold, design: .rounded))

                Text("Download a pinned Gemma 4 model, keep it on-device, and run LiteRT-LM inference from a tvOS-native sample app.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 16) {
                    TVStatusBadge(
                        title: viewModel.statusTitle,
                        message: viewModel.statusMessage,
                        systemImage: statusIcon,
                        tint: statusTint
                    )

                    Link(destination: viewModel.selectedModel.huggingFacePageURL) {
                        Label("Model Source", systemImage: "link")
                            .frame(minWidth: 220)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.18))
                }
            }
        }
    }

    private var modelPanel: some View {
        TVPanel {
            VStack(alignment: .leading, spacing: 18) {
                tvSectionLabel("Model Library", systemImage: "shippingbox.fill")

                ForEach(ExampleModelCatalog.all) { model in
                    Button {
                        viewModel.selectModel(model)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(model.displayName)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white)

                                Spacer()

                                if viewModel.selectedModel == model {
                                    Label("Selected", systemImage: "checkmark.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.green)
                                }
                            }

                            Text(model.summary)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 16) {
                                tvMetaPill("Size", model.sizeDescription)
                                tvMetaPill("File", model.fileName, monospaced: true)
                                tvMetaPill(
                                    "Storage",
                                    viewModel.localModelURL != nil && viewModel.selectedModel == model ? "Local" : "Remote"
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                        .background(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(viewModel.selectedModel == model ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(viewModel.selectedModel == model ? Color.white.opacity(0.28) : Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var actionPanel: some View {
        TVPanel {
            VStack(alignment: .leading, spacing: 18) {
                tvSectionLabel("Actions", systemImage: "sparkles.rectangle.stack.fill")

                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.selectedModel.displayName)
                        .font(.title2.weight(.bold))
                    Text(viewModel.localModelPath)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if viewModel.isDownloading, let progress = viewModel.downloadProgress {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Download Progress")
                                .font(.headline)
                            Spacer()
                            Text(progress.percentDescription)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: progress.fractionCompleted)

                        Text("\(progress.completedDescription) of \(progress.totalDescription)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    viewModel.downloadSelectedModel()
                } label: {
                    Label(viewModel.isDownloading ? "Downloading Model" : "Download Model", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canDownloadSelectedModel)

                Button(role: .destructive) {
                    viewModel.deleteSelectedModel()
                } label: {
                    Label("Delete Local Model", systemImage: "trash.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canDeleteSelectedModel)

                Button {
                    viewModel.runInference()
                } label: {
                    Label(viewModel.isRunning ? "Running Inference" : "Run Inference", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!viewModel.canRunInference)
            }
        }
        .frame(width: 430, alignment: .top)
    }

    private var promptPanel: some View {
        TVPanel {
            VStack(alignment: .leading, spacing: 18) {
                tvSectionLabel("Prompt Studio", systemImage: "text.bubble.fill")

                Text("Apple TV works better with curated prompts than tiny text fields, so this sample gives you large presets and a simple editor for quick iteration.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Edit the active prompt", text: $draftPrompt, axis: .vertical)
                    .font(.body)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08))
                    )

                HStack(spacing: 12) {
                    Button {
                        viewModel.setPrompt(draftPrompt, source: "tvOS editor")
                    } label: {
                        Label("Apply Prompt", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftPrompt == viewModel.prompt)

                    Button {
                        draftPrompt = viewModel.prompt
                    } label: {
                        Label("Revert", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(draftPrompt == viewModel.prompt)
                }

                HStack(alignment: .top, spacing: 16) {
                    ForEach(TVPromptCatalog.all) { preset in
                        Button {
                            draftPrompt = preset.prompt
                            viewModel.setPrompt(preset.prompt, source: "tvOS preset \(preset.id)")
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(preset.title)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text(preset.summary)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Text(preset.prompt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                            .frame(maxWidth: .infinity, minHeight: 200, alignment: .leading)
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var responsePanel: some View {
        TVPanel {
            VStack(alignment: .leading, spacing: 18) {
                tvSectionLabel("Response", systemImage: "waveform.and.magnifyingglass")

                if !viewModel.errorMessage.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(viewModel.errorMessage)
                            .font(.body)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                if viewModel.isRunning {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Generating on Apple TV...")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else if viewModel.response.isEmpty {
                    Text("No response yet. Download a model, choose a prompt, and run on-device inference.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    Text(viewModel.response)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
    }

    private func benchmarkPanel(_ benchmark: InferenceBenchmark) -> some View {
        TVPanel {
            VStack(alignment: .leading, spacing: 16) {
                tvSectionLabel("Benchmark", systemImage: "speedometer")

                HStack(spacing: 16) {
                    tvMetricCard(title: "Initialization", value: benchmark.initializationDescription)
                    tvMetricCard(title: "Time To First Token", value: benchmark.timeToFirstTokenDescription)
                }
            }
        }
    }

    private var statusTint: Color {
        if !viewModel.errorMessage.isEmpty { return .red }
        if viewModel.isRunning || viewModel.isDownloading { return .orange }
        if viewModel.localModelURL != nil { return .green }
        return .white.opacity(0.7)
    }

    private var statusIcon: String {
        if !viewModel.errorMessage.isEmpty { return "exclamationmark.triangle.fill" }
        if viewModel.isRunning { return "sparkles" }
        if viewModel.isDownloading { return "arrow.down.circle.fill" }
        if viewModel.localModelURL != nil { return "checkmark.circle.fill" }
        return "circle.dotted"
    }

    private func tvSectionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private func tvMetaPill(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func tvMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct TVPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09))
            )
    }
}

private struct TVStatusBadge: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 54, height: 54)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    TVContentView(viewModel: InferenceViewModel())
}
