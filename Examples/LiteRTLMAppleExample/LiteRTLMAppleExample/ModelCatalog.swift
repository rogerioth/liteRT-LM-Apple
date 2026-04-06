import Foundation

struct ExampleModelDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let modelID: String
    let commitHash: String
    let fileName: String
    let sizeInBytes: Int64
    let summary: String

    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(modelID)/resolve/\(commitHash)/\(fileName)?download=true")!
    }

    var huggingFacePageURL: URL {
        URL(string: "https://huggingface.co/\(modelID)")!
    }

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }
}

enum ExampleModelCatalog {
    static let gemma4E2B = ExampleModelDescriptor(
        id: "gemma-4-e2b",
        displayName: "Gemma 4 E2B",
        modelID: "litert-community/gemma-4-E2B-it-litert-lm",
        commitHash: "7fa1d78473894f7e736a21d920c3aa80f950c0db",
        fileName: "gemma-4-E2B-it.litertlm",
        sizeInBytes: 2_583_085_056,
        summary: "Smallest pinned example in this repo. Best starting point for verifying the download and inference path."
    )

    static let gemma4E4B = ExampleModelDescriptor(
        id: "gemma-4-e4b",
        displayName: "Gemma 4 E4B",
        modelID: "litert-community/gemma-4-E4B-it-litert-lm",
        commitHash: "9695417f248178c63a9f318c6e0c56cb917cb837",
        fileName: "gemma-4-E4B-it.litertlm",
        sizeInBytes: 3_654_467_584,
        summary: "Larger pinned example for a stronger quality baseline when device storage and memory budget allow it."
    )

    static let all: [ExampleModelDescriptor] = [
        gemma4E2B,
        gemma4E4B,
    ]

    static let defaultModel = gemma4E2B
}
