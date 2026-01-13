import Foundation
import SwiftUI
import Progression

// MARK: - Task Progress View

/// A hierarchical tree view for displaying all tasks in an executor.
///
/// This view automatically updates when tasks are added, removed, or their
/// state changes. It displays tasks with their progress bars, step names,
/// and action buttons.
///
/// ## Usage
///
/// ```swift
/// // Default layout (name above progress bar)
/// TaskProgressView(executor: myExecutor)
///
/// // Custom layout using a ViewBuilder closure
/// TaskProgressView(executor: myExecutor) { task in
///     HStack {
///         Text(task.name)
///         ProgressBarView(progress: Double(task.progress ?? 0))
///     }
/// }
/// ```
///
/// ## Alternative Layouts
///
/// ```swift
/// // Progress bar above task name
/// TaskProgressView.progressAbove(executor: myExecutor)
///
/// // Compact layout with inline progress
/// TaskProgressView.compact(executor: myExecutor)
/// ```
///
/// ## Topics
///
/// ### Types
///
/// - ``DefaultRowContent`` - The default row layout
@MainActor
public struct TaskProgressView<Content: View>: View {
    /// The task executor to observe.
    public let executor: TaskExecutor

    /// A closure that creates the content for each task row.
    public let content: (TaskSnapshot) -> Content

    /// Internal state for the list of tasks.
    @State private var tasks: [TaskSnapshot] = []

    /// Creates a TaskProgressView with the default content layout.
    ///
    /// The default layout displays the task name above a progress bar,
    /// with an optional step name subtitle.
    ///
    /// - Parameter executor: The task executor to observe.
    public init(executor: TaskExecutor) where Content == DefaultRowContent {
        self.executor = executor
        self.content = { DefaultRowContent(task: $0) }
    }

    /// Creates a TaskProgressView with custom content layout.
    ///
    /// - Parameters:
    ///   - executor: The task executor to observe.
    ///   - content: A closure that creates the content for each task row.
    public init(executor: TaskExecutor, @ViewBuilder content: @escaping (TaskSnapshot) -> Content) {
        self.executor = executor
        self.content = content
    }

    public var body: some View {
        taskList
            .task {
                for await graph in executor.progressStream {
                    tasks = graph.tasks
                }
            }
    }

    /// The task list view.
    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(tasks) { task in
                    TaskRowView(
                        task: task,
                        depth: 0,
                        executor: executor,
                        content: content
                    )
                    .id(task.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
                }
            }
            .padding()
        }
        .animation(.easeInOut(duration: 0.2), value: tasks.map { $0.progressHash })
    }
}

// MARK: - Task Row View

/// A row representing a single task with its subtasks.
///
/// This is a private implementation detail of ``TaskProgressView``.
@MainActor
private struct TaskRowView<Content: View>: View {
    /// The task snapshot to display.
    public let task: TaskSnapshot

    /// The current nesting depth (for indentation).
    public let depth: Int

    /// The task executor for action handlers.
    public let executor: TaskExecutor

    /// The content closure for rendering the task.
    public let content: (TaskSnapshot) -> Content

    public var body: some View {
        HStack(spacing: 0) {
            // Main content
            VStack(alignment: .leading, spacing: 4) {
                // Custom content
                content(task)
                    .padding(.leading, CGFloat(depth) * 8)

                // Subtasks (hide all if parent has failed)
                if !task.isFailed && !task.children.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(task.children.filter { !$0.isFailed }) { child in
                            SubtaskRowView(
                                child: child,
                                depth: depth + 1,
                                executor: executor,
                                content: content
                            )
                            .id(child.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                        }
                    }
                    .padding(.leading, 16)
                    .animation(.easeInOut(duration: 0.2), value: task.children.map { $0.progressHash })
                }
            }

            Spacer(minLength: 8)

            // Action buttons gutter (only for top-level tasks, pinned to top)
            if depth == 0 {
                actionButtons
                    .frame(width: 80, alignment: .trailing)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, depth == 0 ? 8 : 0)
    }

    /// The action buttons for the task.
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Pause/Resume button
            if task.options.isPausable && task.isRunning {
                if task.isPaused {
                    Button { Task { await executor.resume(taskID: task.id) } } label: {
                        Image(systemName: "play.circle.fill")
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { Task { await executor.pause(taskID: task.id) } } label: {
                        Image(systemName: "pause.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }

            // Cancel button
            if task.options.isCancellable && task.isRunning {
                Button { Task { await executor.cancel(taskID: task.id) } } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }

            // Dismiss button for failed/cancelled tasks
            if task.isFailed || task.status == .cancelled {
                Button { Task { await executor.remove(taskID: task.id) } } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Subtask Row View

/// A row representing a subtask.
///
/// This is a private implementation detail of ``TaskProgressView``.
@MainActor
private struct SubtaskRowView<Content: View>: View {
    /// The subtask snapshot to display.
    public let child: TaskSnapshot

    /// The current nesting depth (for indentation).
    public let depth: Int

    /// The task executor for action handlers.
    public let executor: TaskExecutor

    /// The content closure for rendering the task.
    public let content: (TaskSnapshot) -> Content

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Only show subtask if not failed (parent shows the error)
            if !child.isFailed {
                content(child)
                    .padding(.leading, CGFloat(depth) * 16)

                // Hide all children if this subtask has failed
                if !child.isFailed && !child.children.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(child.children.filter { !$0.isFailed }) { grandchild in
                            SubtaskRowView(
                                child: grandchild,
                                depth: depth + 1,
                                executor: executor,
                                content: content
                            )
                            .id(grandchild.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                        }
                    }
                    .padding(.leading, 8)
                    .animation(.easeInOut(duration: 0.2), value: child.children.map { $0.progressHash })
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Default Row Content

/// The default row content layout.
///
/// Displays the task name with an optional step name subtitle, and a progress
/// bar below. If the task failed, displays the error message instead of the
/// progress bar.
///
/// ## Example
///
/// ```
/// Task Name — Step Name
/// [██████████░░░░] 75%
/// ```
public struct DefaultRowContent: View {
    /// The task snapshot to display.
    public let task: TaskSnapshot

    /// Creates a new default row content view.
    public init(task: TaskSnapshot) { self.task = task }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(task.name)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                if let step = task.stepName {
                    Text("–")
                    Text(step)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let error = task.errorDescription {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            } else {
                ProgressBarView(progress: progressValue)
            }
        }
    }

    /// The progress value to display.
    private var progressValue: Double? {
        // Show actual progress if paused
        if task.isPaused {
            return task.progress.map(Double.init)
        }

        switch task.status {
        case .running: return task.progress.map(Double.init)
        case .completed: return 1.0
        case .failed: return task.progress.map(Double.init) ?? 1.0
        case .cancelled: return task.progress.map(Double.init) ?? 0
        case .pending: return nil
        }
    }
}

// MARK: - Alternative Row Layouts

extension TaskProgressView where Content == AnyView {
    /// Creates a TaskProgressView with progress bar above the task name.
    ///
    /// - Parameter executor: The task executor to observe.
    /// - Returns: A new TaskProgressView instance.
    public static func progressAbove(executor: TaskExecutor) -> TaskProgressView<AnyView> {
        TaskProgressView(executor: executor) { task in
            AnyView(VStack(alignment: .leading, spacing: 4) {
                ProgressBarView(progress: progress(for: task))
                HStack {
                    Text(task.name)
                    if let step = task.stepName {
                        Text("— \(step)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            })
        }
    }

    /// Creates a compact TaskProgressView with inline layout.
    ///
    /// The task name and progress bar are displayed on the same line.
    ///
    /// - Parameter executor: The task executor to observe.
    /// - Returns: A new TaskProgressView instance.
    public static func compact(executor: TaskExecutor) -> TaskProgressView<AnyView> {
        TaskProgressView(executor: executor) { task in
            AnyView(HStack {
                Text(task.name)
                Spacer()
                ProgressBarView(progress: progress(for: task))
                    .frame(width: 100)
                if let step = task.stepName {
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            })
        }
    }

    /// Calculates the progress value for display.
    private static func progress(for task: TaskSnapshot) -> Double? {
        // Show actual progress if paused
        if task.isPaused {
            return task.progress.map(Double.init)
        }

        switch task.status {
        case .running: return task.progress.map(Double.init)
        case .completed: return 1.0
        case .failed: return task.progress.map(Double.init) ?? 1.0
        case .cancelled: return task.progress.map(Double.init) ?? 0
        case .pending: return nil
        }
    }
}

#Preview("Live Preview") {
    LiveTaskPreview()
}

@MainActor
final class LiveTaskPreviewModel: ObservableObject {
    let executor = TaskExecutor()

    func startTask() {
        Task {
            let _ = await executor.addTask(
                name: "Data Import \(UUID().uuidString.prefix(4))",
                options: .interactive
            ) { context in
                try await context.report(.named("Initializing..."))
                try await Task.sleep(for: .milliseconds(300))

                try await context.push("Downloading files") { subContext in
                    try await subContext.report(.named("Downloading files..."))
                    for i in 1...5 {
                        try await Task.sleep(for: .milliseconds(200))
                        try await subContext.report(.progress(Float(i) / 5.0))
                    }
                }

                try await context.report(.progress(0.3))

                try await context.push("Parsing records") { parseContext in
                    try await parseContext.report(.named("Parsing records..."))
                    for batch in 1...3 {
                        try await parseContext.push("Batch \(batch)/3") { batchContext in
                            try await batchContext.report(.named("Batch \(batch)/3"))
                            for i in 1...4 {
                                try await Task.sleep(for: .milliseconds(150))
                                try await batchContext.report(.progress(Float(i) / 4.0))
                            }
                        }
                    }
                }

                try await context.report(.progress(0.7))

                try await context.push("Exporting") { exportContext in
                    try await exportContext.report(.named("Exporting..."))
                    for i in 1...10 {
                        try await Task.sleep(for: .milliseconds(100))
                        try await exportContext.report(.progress(Float(i) / 10.0))
                    }
                }

                try await context.report(.progress(1.0))
            }
        }
    }

    func cancelAll() {
        Task { await executor.cancelAll() }
    }

    func clearCompleted() {
        Task { await executor.removeCompletedTasks() }
    }
}

struct LiveTaskPreview: View {
    @StateObject private var model = LiveTaskPreviewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.startTask()
                } label: {
                    Label("Start Task", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    model.cancelAll()
                } label: {
                    Label("Cancel All", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Clear Completed") {
                    model.clearCompleted()
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            TaskProgressView(executor: model.executor)
        }
    }
}
