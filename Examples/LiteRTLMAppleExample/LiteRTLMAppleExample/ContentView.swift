import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: InferenceViewModel

    private let accent = Color(red: 0.14, green: 0.34, blue: 0.28)
    private let warmBackground = Color(red: 0.96, green: 0.95, blue: 0.92)
    private let sand = Color(red: 0.90, green: 0.86, blue: 0.78)
    private let cardBackground = Color.white.opacity(0.78)

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    summaryRow
                    modelCard
                    promptCard
                    responseCard
                }
                .padding(20)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            viewModel.startIfNeeded()
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                warmBackground,
                Color(red: 0.91, green: 0.94, blue: 0.89),
                Color(red: 0.86, green: 0.91, blue: 0.89),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(sand.opacity(0.4))
                .frame(width: 260, height: 260)
                .blur(radius: 8)
                .offset(x: 90, y: -90)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LiteRT-LM-Apple")
                .font(.system(size: 44, weight: .semibold, design: .serif))
                .foregroundStyle(Color(red: 0.10, green: 0.20, blue: 0.18))

            Text("A reference iOS app for downloading LiteRT-LM models into local storage and running fully on-device inference through the packaged C API.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TagLabel(title: "Local Models")
                TagLabel(title: "Swift Package")
                TagLabel(title: "On-Device Inference")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        }
    }

    private var summaryRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                summaryTile(title: "Status", value: viewModel.statusTitle, detail: viewModel.statusAccentName)
                summaryTile(title: "Selected Model", value: viewModel.selectedModel.displayName, detail: viewModel.selectedModel.sizeDescription)
                summaryTile(title: "Storage", value: viewModel.localModelURL == nil ? "Remote Only" : "Available Locally", detail: viewModel.localModelURL == nil ? "Download required" : "Ready to run")
            }

            VStack(spacing: 14) {
                summaryTile(title: "Status", value: viewModel.statusTitle, detail: viewModel.statusAccentName)
                summaryTile(title: "Selected Model", value: viewModel.selectedModel.displayName, detail: viewModel.selectedModel.sizeDescription)
                summaryTile(title: "Storage", value: viewModel.localModelURL == nil ? "Remote Only" : "Available Locally", detail: viewModel.localModelURL == nil ? "Download required" : "Ready to run")
            }
        }
    }

    private func summaryTile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(red: 0.10, green: 0.20, blue: 0.18))

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        }
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: "Model",
                subtitle: viewModel.statusMessage
            )

            Picker(
                "Model",
                selection: Binding(
                    get: { viewModel.selectedModel },
                    set: { viewModel.selectModel($0) }
                )
            ) {
                ForEach(ExampleModelCatalog.all) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.selectedModel.summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    metadataLine(label: "Package Size", value: viewModel.selectedModel.sizeDescription)
                    metadataLine(label: "Model File", value: viewModel.selectedModel.fileName)
                }

                VStack(alignment: .leading, spacing: 10) {
                    metadataLine(label: "Package Size", value: viewModel.selectedModel.sizeDescription)
                    metadataLine(label: "Model File", value: viewModel.selectedModel.fileName)
                }
            }

            Link(destination: viewModel.selectedModel.huggingFacePageURL) {
                Label("View Model Source", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(accent)

            if let progress = viewModel.downloadProgress, viewModel.isDownloading {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Download Progress")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(progress.percentDescription)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: progress.fractionCompleted)
                        .tint(accent)

                    Text("\(progress.completedDescription) of \(progress.totalDescription)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Local Path")
                    .font(.subheadline.weight(.semibold))

                Text(viewModel.localModelPath)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 12) {
                Button(action: viewModel.downloadSelectedModel) {
                    Label(viewModel.isDownloading ? "Downloading..." : "Download Model", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(viewModel.isDownloading || viewModel.isRunning)

                Button(action: viewModel.deleteSelectedModel) {
                    Label("Delete Local Copy", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(viewModel.localModelURL == nil || viewModel.isDownloading || viewModel.isRunning)
            }
        }
        .padding(24)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: "Prompt",
                subtitle: "The example uses the LiteRT-LM conversation API and keeps the prompt entirely local once the model has been downloaded."
            )

            TextEditor(text: $viewModel.prompt)
                .font(.body)
                .padding(14)
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            HStack {
                Text("Tip: the first run can be slower while LiteRT-LM warms local cache artifacts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: viewModel.runInference) {
                    Label(viewModel.isRunning ? "Running..." : "Run Inference", systemImage: "sparkles.rectangle.stack.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(viewModel.localModelURL == nil || viewModel.isDownloading || viewModel.isRunning)
            }
        }
        .padding(24)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        }
    }

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: "Response",
                subtitle: "The result below is parsed from the JSON response returned by the LiteRT-LM conversation object."
            )

            if !viewModel.errorMessage.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(red: 0.63, green: 0.33, blue: 0.16))

                    Text(viewModel.errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(Color(red: 0.39, green: 0.18, blue: 0.09))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(Color(red: 0.98, green: 0.91, blue: 0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Group {
                if viewModel.isRunning {
                    VStack(alignment: .leading, spacing: 14) {
                        ProgressView()
                            .tint(accent)
                        Text("Generating a local response with the selected model...")
                            .font(.body.weight(.medium))
                        Text("This runs through the same C API surface that the package exposes to any consumer app.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    Text(viewModel.response.isEmpty ? "No response yet. Download a model, enter a prompt, and run inference." : viewModel.response)
                        .font(.body)
                        .foregroundStyle(viewModel.response.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }

            if let benchmark = viewModel.benchmark {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        benchmarkChip(title: "Initialization", value: benchmark.initializationDescription)
                        benchmarkChip(title: "Time To First Token", value: benchmark.timeToFirstTokenDescription)
                    }

                    VStack(spacing: 12) {
                        benchmarkChip(title: "Initialization", value: benchmark.initializationDescription)
                        benchmarkChip(title: "Time To First Token", value: benchmark.timeToFirstTokenDescription)
                    }
                }
            }
        }
        .padding(24)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        }
    }

    private func metadataLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(Color(red: 0.10, green: 0.20, blue: 0.18))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benchmarkChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color(red: 0.10, green: 0.20, blue: 0.18))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color(red: 0.10, green: 0.20, blue: 0.18))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TagLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.72), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
            }
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.14, green: 0.34, blue: 0.28))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .foregroundStyle(Color(red: 0.16, green: 0.24, blue: 0.22))
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

#Preview {
    ContentView(viewModel: InferenceViewModel())
}
