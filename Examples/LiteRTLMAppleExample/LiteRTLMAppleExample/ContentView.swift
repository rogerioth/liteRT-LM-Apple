#if !os(tvOS)
import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @ObservedObject var viewModel: InferenceViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    modelCard
                    promptCard
                    responseCard
                    if let benchmark = viewModel.benchmark {
                        benchmarkCard(benchmark)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("LiteRT-LM")
            .toolbar {
                ToolbarItem {
                    Link(destination: viewModel.selectedModel.huggingFacePageURL) {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Model source")
                }
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
        .task { viewModel.startIfNeeded() }
    }

    // MARK: - Status

    private var statusCard: some View {
        Card {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: statusIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.statusTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if viewModel.isRunning || viewModel.isDownloading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var statusColor: Color {
        if !viewModel.errorMessage.isEmpty { return .red }
        if viewModel.isRunning || viewModel.isDownloading { return .orange }
        if viewModel.localModelURL != nil { return .green }
        return .secondary
    }

    private var statusIcon: String {
        if !viewModel.errorMessage.isEmpty { return "exclamationmark.triangle.fill" }
        if viewModel.isRunning { return "sparkles" }
        if viewModel.isDownloading { return "arrow.down.circle.fill" }
        if viewModel.localModelURL != nil { return "checkmark.circle.fill" }
        return "circle.dotted"
    }

    // MARK: - Model

    private var modelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(icon: "shippingbox", title: "Model")

                Picker("Model", selection: Binding(
                    get: { viewModel.selectedModel },
                    set: { viewModel.selectModel($0) }
                )) {
                    ForEach(ExampleModelCatalog.all) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.segmented)

                Text(viewModel.selectedModel.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 6) {
                    InfoRow(label: "Size", value: viewModel.selectedModel.sizeDescription)
                    Divider()
                    InfoRow(label: "File", value: viewModel.selectedModel.fileName, monospaced: true)
                    Divider()
                    InfoRow(
                        label: "Storage",
                        value: viewModel.localModelURL == nil ? "Not downloaded" : "Local"
                    )
                }
                .padding(.vertical, 4)

                if viewModel.isDownloading, let progress = viewModel.downloadProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Downloading")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(progress.percentDescription)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: progress.fractionCompleted)
                        Text("\(progress.completedDescription) of \(progress.totalDescription)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        viewModel.downloadSelectedModel()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle")
                            Text(viewModel.isDownloading ? "Downloading" : "Download")
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 22)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(viewModel.isDownloading || viewModel.isRunning || viewModel.localModelURL != nil)

                    Button(role: .destructive) {
                        viewModel.deleteSelectedModel()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("Delete")
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 22)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(viewModel.localModelURL == nil || viewModel.isDownloading || viewModel.isRunning)
                }
            }
        }
    }

    // MARK: - Prompt

    private var promptCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(icon: "text.bubble", title: "Prompt")

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.appSecondaryBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08))
                        )

                    TextEditor(text: $viewModel.prompt)
                        .font(.footnote)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 120)
                }

                Button {
                    viewModel.runInference()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text(viewModel.isRunning ? "Running" : "Run Inference")
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(viewModel.localModelURL == nil || viewModel.isDownloading || viewModel.isRunning)
            }
        }
    }

    // MARK: - Response

    private var responseCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(icon: "sparkles", title: "Response")

                if !viewModel.errorMessage.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                        Text(viewModel.errorMessage)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if viewModel.isRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Generating…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if viewModel.response.isEmpty {
                    Text("No response yet. Download a model, enter a prompt, and run inference.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Text(viewModel.response)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    // MARK: - Benchmark

    private func benchmarkCard(_ benchmark: InferenceBenchmark) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(icon: "speedometer", title: "Benchmark")
                VStack(spacing: 6) {
                    InfoRow(label: "Initialization", value: benchmark.initializationDescription, monospaced: true)
                    Divider()
                    InfoRow(label: "Time to first token", value: benchmark.timeToFirstTokenDescription, monospaced: true)
                }
            }
        }
    }
}

// MARK: - Building blocks

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.appCardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}

private struct SectionLabel: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced ? .footnote.monospaced() : .footnote)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private extension Color {
    static var appGroupedBackground: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(uiColor: .systemGroupedBackground)
#endif
    }

    static var appSecondaryBackground: Color {
#if os(macOS)
        Color(nsColor: .controlBackgroundColor)
#else
        Color(uiColor: .secondarySystemBackground)
#endif
    }

    static var appCardBackground: Color {
#if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
#else
        Color(uiColor: .secondarySystemGroupedBackground)
#endif
    }
}

#Preview("Light") {
    ContentView(viewModel: InferenceViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView(viewModel: InferenceViewModel())
        .preferredColorScheme(.dark)
}
#endif
