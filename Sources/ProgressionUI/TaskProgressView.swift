//
//  TaskProgressContainer.swift
//  Progression
//
//  Created by Mark Onyschuk on 1/13/26.
//  Copyright © 2026 by Dimension North Inc, All Rights Reserved.
//

import SwiftUI
import Progression

// MARK: - Progress Container

/// An abstract view that coordinates with a task executor and provides
/// task snapshots to a content closure.
///
/// This type handles the infrastructure of observing the executor's
/// progress stream, while delegating the actual rendering to the content
/// closure. This separation allows different layout implementations
/// to be used with the same executor coordination logic.
///
/// ## Example
///
/// ```swift
/// ProgressContainer(executor: myExecutor) { tasks in
///     ForEach(tasks) { task in
///         Text(task.name)
///     }
/// }
/// ```
@MainActor
public struct ProgressContainer<Content: View>: View {
    /// The task executor to observe.
    public let executor: TaskExecutor

    /// A closure that receives the current tasks and returns the view content.
    public let content: ([TaskSnapshot]) -> Content

    /// Internal state for the list of tasks.
    @State private var tasks: [TaskSnapshot] = []

    /// Creates a progress view with a custom content closure.
    ///
    /// - Parameters:
    ///   - executor: The task executor to observe.
    ///   - content: A closure that receives the current tasks and returns the view content.
    public init(executor: TaskExecutor, @ViewBuilder content: @escaping ([TaskSnapshot]) -> Content) {
        self.executor = executor
        self.content = content
    }

    public var body: some View {
        content(tasks)
            .task {
                for await graph in executor.progressStream {
                    tasks = graph.tasks
                }
            }
    }
}

// MARK: - Progress Layout

/// A type that defines how to render a collection of tasks.
///
/// Layouts receive the task snapshots and an executor reference,
/// enabling them to render tasks with appropriate actions.
///
/// You can create custom layouts by defining a view that takes
/// tasks and an executor as parameters.
///
/// ## Example
///
/// ```swift
/// struct PieChartLayout: View {
///     let tasks: [TaskSnapshot]
///     let executor: TaskExecutor
///
///     var body: some View {
///         // Custom rendering
///     }
/// }
///
/// ProgressContainer(executor: myExecutor) { tasks in
///     PieChartLayout(tasks: tasks, executor: myExecutor)
/// }
/// ```
///
/// ## Built-in Layouts
///
/// - ``ListLayout`` - A hierarchical tree view of tasks
public protocol ProgressLayout {
    // This protocol serves as documentation for custom layout implementations.
    // Layouts are simply views that accept tasks and an executor parameter.
}

// MARK: - List Layout

/// A hierarchical tree layout for displaying tasks.
///
/// This layout displays tasks with their subtasks in an indented
/// tree structure, supporting all standard task actions (pause,
/// resume, cancel, dismiss).
///
/// ## Usage
///
/// ```swift
/// ListLayout(tasks: tasks, executor: executor) { task in
///     DefaultRowContent(task: task)
/// }
/// ```
///
/// ## Topics
///
/// - ``DefaultRowContent`` - The default row content for list items
public struct ListLayout<RowContent: View>: View {
    /// The tasks to render.
    public let tasks: [TaskSnapshot]

    /// The executor for action handlers.
    public let executor: TaskExecutor

    /// The content closure for rendering individual task rows.
    public let content: (TaskSnapshot) -> RowContent

    /// Creates a list layout.
    ///
    /// - Parameters:
    ///   - tasks: The tasks to display.
    ///   - executor: The executor for action handlers.
    ///   - content: A closure that renders each task row.
    public init(
        tasks: [TaskSnapshot],
        executor: TaskExecutor,
        @ViewBuilder content: @escaping (TaskSnapshot) -> RowContent
    ) {
        self.tasks = tasks
        self.executor = executor
        self.content = content
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(tasks) { task in
                    ListTaskRow(
                        task: task,
                        depth: 0,
                        executor: executor,
                        content: content
                    )
                    .id(task.id)
                    .transition(
                        .asymmetric(
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

// MARK: - List Task Row

/// A row representing a single task with its subtasks.
///
/// This is a private implementation detail of ``ListLayout``.
@MainActor
private struct ListTaskRow<Content: View>: View {
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
                            ListSubtaskRow(
                                child: child,
                                depth: depth + 1,
                                executor: executor,
                                content: content
                            )
                            .id(child.id)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                ))
                        }
                    }
                    .padding(.leading, 16)
                    .animation(
                        .easeInOut(duration: 0.2), value: task.children.map { $0.progressHash })
                }
            }

            Spacer(minLength: 8)

            // Action buttons gutter (only for top-level tasks, pinned to top)
            if depth == 0 {
                listActionButtons
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
    private var listActionButtons: some View {
        HStack(spacing: 8) {
            // Pause/Resume button
            if task.options.isPausable && task.isRunning {
                if task.isPaused {
                    Button {
                        Task { await executor.resume(taskID: task.id) }
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await executor.pause(taskID: task.id) }
                    } label: {
                        Image(systemName: "pause.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            // Cancel button
            if task.options.isCancellable && task.isRunning {
                Button {
                    Task { await executor.cancel(taskID: task.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // Retry button for retryable failed/cancelled tasks
            if task.options.canRetry && (task.isFailed || task.status == .cancelled) {
                Button {
                    Task { await executor.retry(taskID: task.id) }
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // Dismiss button for failed/cancelled tasks (always last)
            if task.isFailed || task.status == .cancelled {
                Button {
                    Task { await executor.remove(taskID: task.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - List Subtask Row

/// A row representing a subtask.
///
/// This is a private implementation detail of ``ListLayout``.
@MainActor
private struct ListSubtaskRow<Content: View>: View {
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
                            ListSubtaskRow(
                                child: grandchild,
                                depth: depth + 1,
                                executor: executor,
                                content: content
                            )
                            .id(grandchild.id)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                ))
                        }
                    }
                    .padding(.leading, 8)
                    .animation(
                        .easeInOut(duration: 0.2), value: child.children.map { $0.progressHash })
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
                ProgressBar(progress)
            }
        }
    }

    /// The progress value to display.
    private var progress: Float? {
        // Show actual progress if paused
        if task.isPaused {
            task.progress

        } else {
            switch task.status {
            case .pending:      nil

            case .running:      task.progress

            case .failed:       task.progress ?? 1.0
            case .cancelled:    task.progress ?? 0

            case .completed:    1.0
            }
        }
    }
}

// MARK: - Task Progress View (Convenience Typealias)

/// A hierarchical tree view for displaying all tasks in an executor.
///
/// This is a convenience typealias that creates a ``ProgressContainer`` with
/// a ``ListLayout`` and ``DefaultRowContent``.
///
/// ```swift
/// TaskProgressView(executor: myExecutor)
/// ```
///
/// For custom layouts, use ``ProgressContainer`` directly:
///
/// ```swift
/// ProgressContainer(executor: myExecutor) { tasks in
///     MyCustomLayout(tasks: tasks, executor: myExecutor)
/// }
/// ```
public typealias TaskProgressView = ProgressContainer<ListLayout<DefaultRowContent>>

extension ProgressContainer where Content == ListLayout<DefaultRowContent> {
    /// Creates a TaskProgressView with the default list layout.
    ///
    /// - Parameter executor: The task executor to observe.
    public init(executor: TaskExecutor) {
        self.executor = executor
        self.content = { tasks in
            ListLayout(tasks: tasks, executor: executor) { task in
                DefaultRowContent(task: task)
            }
        }
    }
}

// MARK: - Previews

#Preview("Live Preview") {
    LiveTaskPreview()
}

@MainActor
@Observable
final class LiveTaskPreviewModel {
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
                    for i in 1 ... 5 {
                        try await Task.sleep(for: .milliseconds(200))
                        try await subContext.report(.progress(Float(i) / 5.0))
                    }
                }

                try await context.report(.progress(0.3))

                try await context.push("Parsing records") { parseContext in
                    try await parseContext.report(.named("Parsing records..."))
                    for batch in 1 ... 3 {
                        try await parseContext.push("Batch \(batch)/3") { batchContext in
                            try await batchContext.report(.named("Batch \(batch)/3"))
                            for i in 1 ... 4 {
                                try await Task.sleep(for: .milliseconds(150))
                                try await batchContext.report(.progress(Float(i) / 4.0))
                            }
                        }
                    }
                }

                try await context.report(.progress(0.7))

                try await context.push("Exporting") { exportContext in
                    try await exportContext.report(.named("Exporting..."))
                    for i in 1 ... 10 {
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
    @State private var model = LiveTaskPreviewModel()

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

            ProgressContainer(executor: model.executor) { tasks in
                ListLayout(tasks: tasks, executor: model.executor) { task in
                    DefaultRowContent(task: task)
                }
            }
        }
    }
}
