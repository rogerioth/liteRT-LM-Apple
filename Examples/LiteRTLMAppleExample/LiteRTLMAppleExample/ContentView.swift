import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: InferenceViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { Color.accentColor }

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    summaryRow
                    modelCard
                    promptCard
                    responseCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .tint(accent)
        .task { viewModel.startIfNeeded() }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.05, green: 0.18, blue: 0.22),
                        Color(red: 0.02, green: 0.05, blue: 0.10),
                      ]
                    : [
                        Color(red: 0.86, green: 0.94, blue: 0.96),
                        Color(red: 0.96, green: 0.95, blue: 0.92),
                      ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.9)
            .ignoresSafeArea()

            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(accent.opacity(colorScheme == .dark ? 0.30 : 0.22))
                        .frame(width: 320, height: 320)
                        .blur(radius: 80)
                        .position(x: proxy.size.width * 0.85, y: proxy.size.height * 0.10)

                    Circle()
                        .fill(Color.purple.opacity(colorScheme == .dark ? 0.25 : 0.16))
                        .frame(width: 280, height: 280)
                        .blur(radius: 90)
                        .position(x: proxy.size.width * 0.10, y: proxy.size.height * 0.85)
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("LiteRT-LM")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("On-device inference for Apple platforms")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusPill
            }

            Text("A reference iOS app for downloading LiteRT-LM models into local storage and running fully on-device inference through the packaged C API.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TagLabel(title: "Local Models", icon: "internaldrive")
                TagLabel(title: "Swift Package", icon: "shippingbox")
                TagLabel(title: "On-Device", icon: "iphone")
            }
        }
        .padding(24)
        .cardBackground()
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.4), lineWidth: 4)
                        .scaleEffect(viewModel.isRunning || viewModel.isDownloading ? 1.6 : 1.0)
                        .opacity(viewModel.isRunning || viewModel.isDownloading ? 0 : 1)
                        .animation(
                            (viewModel.isRunning || viewModel.isDownloading)
                                ? .easeOut(duration: 1.2).repeatForever(autoreverses: false)
                                : .default,
                            value: viewModel.isRunning || viewModel.isDownloading
                        )
                )
            Text(viewModel.statusTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }

    private var statusColor: Color {
        if !viewModel.errorMessage.isEmpty { return .red }
        if viewModel.isRunning || viewModel.isDownloading { return .orange }
        if viewModel.localModelURL != nil { return .green }
        return .secondary
    }

    // MARK: - Summary

    private var summaryRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                summaryTile(icon: "bolt.fill", title: "Status", value: viewModel.statusTitle, detail: viewModel.statusAccentName)
                summaryTile(icon: "shippingbox.fill", title: "Model", value: viewModel.selectedModel.displayName, detail: viewModel.selectedModel.sizeDescription)
                summaryTile(icon: "internaldrive.fill", title: "Storage", value: viewModel.localModelURL == nil ? "Remote" : "Local", detail: viewModel.localModelURL == nil ? "Download required" : "Ready to run")
            }

            VStack(spacing: 12) {
                summaryTile(icon: "bolt.fill", title: "Status", value: viewModel.statusTitle, detail: viewModel.statusAccentName)
                summaryTile(icon: "shippingbox.fill", title: "Model", value: viewModel.selectedModel.displayName, detail: viewModel.selectedModel.sizeDescription)
                summaryTile(icon: "internaldrive.fill", title: "Storage", value: viewModel.localModelURL == nil ? "Remote" : "Local", detail: viewModel.localModelURL == nil ? "Download required" : "Ready to run")
            }
        }
    }

    private func summaryTile(icon: String, title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground(cornerRadius: 20)
    }

    // MARK: - Model card

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(icon: "shippingbox.fill", title: "Model", subtitle: viewModel.statusMessage)

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
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    metadataLine(label: "Package Size", value: viewModel.selectedModel.sizeDescription)
                    metadataLine(label: "Model File", value: viewModel.selectedModel.fileName)
                }

                VStack(alignment: .leading, spacing: 12) {
                    metadataLine(label: "Package Size", value: viewModel.selectedModel.sizeDescription)
                    metadataLine(label: "Model File", value: viewModel.selectedModel.fileName)
                }
            }

            Link(destination: viewModel.selectedModel.huggingFacePageURL) {
                Label("View Model Source", systemImage: "arrow.up.right.square.fill")
                    .font(.subheadline.weight(.semibold))
            }

            if let progress = viewModel.downloadProgress, viewModel.isDownloading {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Downloading", systemImage: "arrow.down.circle")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(progress.percentDescription)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: progress.fractionCompleted)
                    Text("\(progress.completedDescription) of \(progress.totalDescription)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Local Path", systemImage: "folder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(viewModel.localModelPath)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 10) {
                Button(action: viewModel.downloadSelectedModel) {
                    Label(viewModel.isDownloading ? "Downloading..." : "Download", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(viewModel.isDownloading || viewModel.isRunning)

                Button(action: viewModel.deleteSelectedModel) {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(viewModel.localModelURL == nil || viewModel.isDownloading || viewModel.isRunning)
            }
        }
        .padding(22)
        .cardBackground()
    }

    // MARK: - Prompt card

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                icon: "text.bubble.fill",
                title: "Prompt",
                subtitle: "Uses the LiteRT-LM conversation API. Stays fully on-device after download."
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )

                TextEditor(text: $viewModel.prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 160)
            }

            HStack(alignment: .center, spacing: 12) {
                Label("First run may be slower while caches warm up.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Button(action: viewModel.runInference) {
                    Label(viewModel.isRunning ? "Running..." : "Run", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(viewModel.localModelURL == nil || viewModel.isDownloading || viewModel.isRunning)
            }
        }
        .padding(22)
        .cardBackground()
    }

    // MARK: - Response card

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                icon: "sparkles",
                title: "Response",
                subtitle: "Parsed from the JSON response returned by the LiteRT-LM conversation."
            )

            if !viewModel.errorMessage.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(viewModel.errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.30))
                )
            }

            Group {
                if viewModel.isRunning {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Generating response...")
                                .font(.body.weight(.semibold))
                        }
                        Text("Running through the LiteRT-LM C API on this device.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else if viewModel.response.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "text.alignleft")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No response yet")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Download a model, enter a prompt, and tap Run.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    Text(viewModel.response)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            if let benchmark = viewModel.benchmark {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        benchmarkChip(icon: "bolt.fill", title: "Initialization", value: benchmark.initializationDescription)
                        benchmarkChip(icon: "timer", title: "Time To First Token", value: benchmark.timeToFirstTokenDescription)
                    }

                    VStack(spacing: 10) {
                        benchmarkChip(icon: "bolt.fill", title: "Initialization", value: benchmark.initializationDescription)
                        benchmarkChip(icon: "timer", title: "Time To First Token", value: benchmark.timeToFirstTokenDescription)
                    }
                }
            }
        }
        .padding(22)
        .cardBackground()
    }

    // MARK: - Helpers

    private func metadataLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benchmarkChip(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.20))
        )
    }

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Card background modifier

private struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
    }
}

private extension View {
    func cardBackground(cornerRadius: CGFloat = 24) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}

// MARK: - Tag

private struct TagLabel: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }
}

// MARK: - Buttons

private struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .shadow(color: Color.accentColor.opacity(isEnabled ? 0.30 : 0), radius: 10, x: 0, y: 4)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
