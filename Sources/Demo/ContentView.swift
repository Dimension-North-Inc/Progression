import SwiftUI
import Progression
import ProgressionUI

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 700, height: 500)
    }
}

struct ContentView: View {
    @StateObject private var model = DemoViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button {
                    model.startTask()
                } label: {
                    Label("Start Task", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)

                Button {
                    model.startFailingTask()
                } label: {
                    Label("Start Failing Task", systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    model.cancelAll()
                } label: {
                    Label("Cancel All", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()

            Divider()

            // Task list
            TaskProgressView(executor: model.executor)
        }
    }
}

@MainActor
final class DemoViewModel: ObservableObject {
    let executor = TaskExecutor()
    @Published var isRunning = false

    func startTask() {
        guard !isRunning else { return }
        isRunning = true

        Task {
            await executor.addTask(
                name: "Data Import \(UUID().uuidString.prefix(4))",
                options: .interactive
            ) { context in
                // Step 1: Initialize
                try await context.report(.named("Initializing import..."))
                try await Task.sleep(for: .milliseconds(500))

                // Step 2: Download
                try await context.push("Downloading data files") { downloadContext in
                    try await downloadContext.report(.named("Downloading data files..."))

                    for i in 1...10 {
                        try await Task.sleep(for: .milliseconds(150))
                        try await downloadContext.report(.progress(Float(i) / 10.0))
                    }
                }

                try await context.report(.progress(0.2))

                // Step 3: Parse
                try await context.push("Parsing records") { parseContext in
                    try await parseContext.report(.named("Parsing records..."))

                    for batch in 1...3 {
                        try await parseContext.push("Batch \(batch)/3") { batchContext in
                            try await batchContext.report(.named("Batch \(batch)/3"))

                            for i in 1...5 {
                                try await Task.sleep(for: .milliseconds(100))
                                try await batchContext.report(.progress(Float(i) / 5.0))
                            }
                        }
                    }
                }

                try await context.report(.progress(0.6))

                // Step 4: Validate
                try await context.push("Validating data") { validateContext in
                    try await validateContext.report(.named("Validating data..."))

                    for i in 1...5 {
                        try await Task.sleep(for: .milliseconds(100))
                        try await validateContext.report(.progress(Float(i) / 5.0))
                    }
                }

                try await context.report(.progress(0.85))

                // Step 5: Index
                try await context.push("Building search index") { indexContext in
                    try await indexContext.report(.named("Building search index..."))

                    for i in 1...10 {
                        try await Task.sleep(for: .milliseconds(50))
                        try await indexContext.report(.progress(Float(i) / 10.0))
                    }
                }

                try await context.report(.progress(1.0))
            }

            isRunning = false
        }
    }

    func cancelAll() {
        Task {
            await executor.cancelAll()
            isRunning = false
        }
    }

    func startFailingTask() {
        Task {
            let _ = await executor.addTask(
                name: "Failing Task \(UUID().uuidString.prefix(4))",
                options: .interactive
            ) { context in
                try await context.report(.named("Starting..."))
                try await Task.sleep(for: .milliseconds(300))

                try await context.push("Step 1") { stepContext in
                    try await stepContext.report(.named("Step 1 in progress..."))
                    try await Task.sleep(for: .milliseconds(200))
                    try await stepContext.report(.progress(0.5))
                }

                try await context.report(.progress(0.3))

                // This subtask will fail
                try await context.push("Failing Step") { stepContext in
                    try await stepContext.report(.named("About to fail..."))
                    try await Task.sleep(for: .milliseconds(200))
                    throw NSError(domain: "DemoError", code: 42, userInfo: [NSLocalizedDescriptionKey: "Something went wrong in the failing step"])
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
