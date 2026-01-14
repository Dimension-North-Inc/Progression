//
//  TaskExecutor.swift
//  Progression
//
//  Created by Mark Onyschuk on 1/13/26.
//  Copyright © 2026 by Dimension North Inc, All Rights Reserved.
//

import Foundation

/// Helper class to hold a task reference for timeout cancellation.
/// This avoids the closure capture issue when a task needs to cancel itself.
final class TaskHolder: @unchecked Sendable {
    var task: Task<Void, Never>?
}

/// Internal implementation of TaskContext that delegates to the executor actor.
final class TaskContextImpl: @unchecked Sendable, TaskContext {
    private weak var executor: TaskExecutor?
    private let taskID: String

    init(executor: TaskExecutor, taskID: String) {
        self.executor = executor
        self.taskID = taskID
    }

    nonisolated func report(_ progress: TaskProgress) async throws {
        try await executor?.reportInternal(taskID: taskID, progress)
    }

    nonisolated func push(
        _ name: String,
        _ step: @escaping @Sendable (any TaskContext) async throws -> Void
    ) async throws {
        try await Task {
            try await executor?.pushInternal(taskID: taskID, name: name, step)
        }.value
    }
}

/// Concrete implementation of `TaskContext` that manages task execution
/// and exposes progress updates via async streams.
public actor TaskExecutor {
    private var tasks: [String: TaskNode] = [:]
    private var currentNodeID: String?
    private var swiftTasks: [String: Task<Void, Never>] = [:]

    private var pauseContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var streamContinuations: [UUID: AsyncStream<TaskGraph>.Continuation] = [:]

    /// Time in seconds to keep completed tasks before automatic cleanup.
    public var completedTaskVisibilityDuration: TimeInterval = 1.0

    /// Sets the visibility duration for completed tasks.
    public func setVisibilityDuration(_ duration: TimeInterval) {
        completedTaskVisibilityDuration = duration
    }

    /// Creates a new task executor.
    public init() {}

    // MARK: - External API

    /// Adds and starts a new task asynchronously.
    ///
    /// - Parameters:
    ///   - name: Display name for the task
    ///   - id: Optional unique identifier. A UUID string is generated if not provided.
    ///   - options: Task execution options (cancellable, pausable, timeout)
    ///   - task: The async task to execute
    /// - Returns: The ID of the added task
    @discardableResult
    public func addTask(
        name: String,
        id: String? = nil,
        options: TaskOptions = .default,
        _ task: @escaping @Sendable (any TaskContext) async throws -> Void
    ) async -> String {
        let taskNode = TaskNode(id: id ?? UUID().uuidString, name: name, options: options)
        taskNode.status = .running
        taskNode.retryHandler = task
        tasks[taskNode.id] = taskNode

        let taskID = taskNode.id
        currentNodeID = taskID

        // Broadcast initial state
        await broadcastGraph()

        // Capture the task in a wrapper for timeout cancellation
        let taskHolder = TaskHolder()
        taskHolder.task = Task {
            let context = TaskContextImpl(executor: self, taskID: taskID)
            do {
                // If a timeout is configured, start a timeout watcher
                if let timeout = options.timeout {
                    Task {
                        try? await Task.sleep(for: timeout)
                        // Timeout expired - cancel the task
                        taskHolder.task?.cancel()
                    }
                }

                try await task(context)
                taskNode.status = .completed
                taskNode.progress = 1.0
                taskNode.completedAt = Date()
            } catch {
                if isCancellationError(error) {
                    // Check if this was a timeout
                    if taskNode.status != .cancelled && options.timeout != nil {
                        taskNode.status = .failed(TaskTimeoutError(taskID: taskID, timeout: options.timeout!))
                    } else {
                        taskNode.status = .cancelled
                    }
                } else {
                    taskNode.status = .failed(error)
                }
            }
            swiftTasks.removeValue(forKey: taskID)
            currentNodeID = nil
            await broadcastGraph()

            // Schedule cleanup after visibility duration
            scheduleCleanup()
        }

        swiftTasks[taskID] = taskHolder.task!
        return taskID
    }

    /// Pauses a specific task and all its children.
    public func pause(taskID: String) {
        guard let task = tasks[taskID], task.options.isPausable else { return }
        pauseRecursive(task)
        Task { await broadcastGraph() }
    }

    private func pauseRecursive(_ node: TaskNode) {
        node.pause()
        for child in node.children {
            pauseRecursive(child)
        }
    }

    /// Resumes a specific task and all its children.
    public func resume(taskID: String) {
        guard let task = tasks[taskID], task.options.isPausable else { return }
        resumeRecursive(task)
        Task { await broadcastGraph() }
    }

    private func resumeRecursive(_ node: TaskNode) {
        node.resume()
        // Resume any waiting continuation for this node
        if let continuation = pauseContinuations.removeValue(forKey: node.id) {
            continuation.resume()
        }
        // Recursively resume children and clean up their continuations
        for child in node.children {
            resumeRecursive(child)
        }
    }

    /// Removes orphaned continuations for a task and all its children.
    private func cleanupContinuations(for node: TaskNode) {
        if let continuation = pauseContinuations.removeValue(forKey: node.id) {
            continuation.resume()
        }
        for child in node.children {
            cleanupContinuations(for: child)
        }
    }

    /// Cancels a specific task.
    public func cancel(taskID: String) {
        guard let task = tasks[taskID], task.options.isCancellable else { return }

        task.status = .cancelled
        task.isPaused = false
        cancelChildren(of: task)

        // Cancel the underlying Swift Task (enables Task.isCancelled checks)
        swiftTasks[taskID]?.cancel()

        // Clean up any orphaned continuations for this task and children
        cleanupContinuations(for: task)

        Task { await broadcastGraph() }

        // Schedule removal after brief visibility
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            // Only remove if still cancelled (not restarted)
            if case .cancelled = task.status {
                tasks.removeValue(forKey: taskID)
                swiftTasks.removeValue(forKey: taskID)
                await broadcastGraph()
            }
        }
    }

    /// Removes a failed or completed task immediately.
    public func remove(taskID: String) {
        guard let task = tasks[taskID] else { return }

        // Mark as cancelled
        task.status = .cancelled
        task.isPaused = false
        cancelChildren(of: task)

        // Clean up any orphaned continuations for this task and children
        cleanupContinuations(for: task)

        // Remove immediately
        tasks.removeValue(forKey: taskID)
        swiftTasks.removeValue(forKey: taskID)
        Task { await broadcastGraph() }
    }

    /// Retries a failed or cancelled task.
    ///
    /// The task must have `canRetry` set to `true` in its options.
    /// This removes the failed/cancelled task and creates a new task with
    /// the same name, options, and task body.
    ///
    /// - Parameter taskID: The ID of the task to retry.
    /// - Returns: The ID of the new retried task, or `nil` if the task
    ///   cannot be retried (either because it doesn't exist or `canRetry` is false).
    @discardableResult
    public func retry(taskID: String) async -> String? {
        guard let task = tasks[taskID] else { return nil }
        guard task.options.canRetry else { return nil }

        // Check that the task is in a retryable state
        switch task.status {
        case .failed, .cancelled:
            break
        default:
            return nil
        }

        // Capture the retry handler before removing the task
        guard let retryHandler = task.retryHandler else { return nil }

        // Remove the old task
        tasks.removeValue(forKey: taskID)
        swiftTasks.removeValue(forKey: taskID)
        cleanupContinuations(for: task)

        // Create a new task with the same parameters
        let newTaskID = await addTask(
            name: task.name,
            id: task.id, // Reuse the same ID
            options: task.options,
            retryHandler
        )

        await broadcastGraph()
        return newTaskID
    }

    /// Cancels all tasks.
    public func cancelAll() {
        for task in tasks.values {
            if task.options.isCancellable {
                task.status = .cancelled
                task.isPaused = false
                cancelChildren(of: task)
                // Clean up orphaned continuations
                cleanupContinuations(for: task)
            }
        }
        Task { await broadcastGraph() }
    }

    /// Removes completed tasks that have exceeded their visibility duration.
    public func removeCompletedTasks() {
        cleanupNow()
    }

    /// Schedules a cleanup after the visibility duration.
    private func scheduleCleanup() {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(completedTaskVisibilityDuration * 1_000_000_000))
            cleanupNow()
        }
    }

    /// Performs cleanup of completed tasks and broadcasts the updated graph.
    private func cleanupNow() {
        let now = Date()
        let cutoff = now.timeIntervalSinceReferenceDate - completedTaskVisibilityDuration

        // First, clean up children within each remaining task
        for task in tasks.values {
            task.cleanupCompletedChildren(olderThan: cutoff)
        }

        // Then remove completed top-level tasks
        tasks = tasks.filter { _, task in
            // Keep running tasks
            if task.isRunning { return true }

            // Keep failed or cancelled tasks (require manual dismissal)
            if case .failed = task.status { return true }
            if case .cancelled = task.status { return true }

            // Only auto-cleanup truly completed tasks
            if case .completed = task.status, let completedAt = task.completedAt {
                return completedAt.timeIntervalSinceReferenceDate >= cutoff
            }

            return true
        }

        Task { await broadcastGraph() }
    }

    /// Returns all tasks as an array, sorted by creation time (oldest first).
    public var allTasks: [TaskNode] {
        Array(tasks.values).sorted { $0.createdAt < $1.createdAt }
    }

    /// An async stream that emits the complete task graph.
    public nonisolated var progressStream: AsyncStream<TaskGraph> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            let streamID = UUID()

            Task {
                await self.registerContinuation(continuation, id: streamID)
            }

            continuation.onTermination = { _ in
                Task {
                    await self.unregisterContinuation(id: streamID)
                }
            }
        }
    }

    // MARK: - Internal Methods

    fileprivate func reportInternal(taskID: String, _ progress: TaskProgress) async throws {
        guard let task = findTask(id: taskID) else { return }

        // Check for cancellation - both Swift Task and Progression status
        // Swift Task cancellation is cooperative and enables Task.isCancelled checks
        if Task.isCancelled {
            throw CancellationError()
        }
        if task.options.isCancellable, task.status == .cancelled {
            throw CancellationError()
        }

        // Wait if paused - loop handles race conditions where isPaused might
        // still be true after resume due to timing between suspension and state update
        while task.isPaused {
            await withCheckedContinuation { continuation in
                pauseContinuations[taskID] = continuation
            }
            // After resuming, re-check cancelled status
            if Task.isCancelled {
                throw CancellationError()
            }
            if task.options.isCancellable, task.status == .cancelled {
                throw CancellationError()
            }
        }

        // Update task
        if !progress.name.isEmpty && progress.name != "Processing" {
            task.stepName = progress.name
        }
        if let completeness = progress.clampedCompleteness {
            task.progress = completeness
        }

        await broadcastGraph()
    }

    /// Finds a task by ID, searching top-level tasks and all children recursively.
    private func findTask(id: String) -> TaskNode? {
        // Check top-level tasks first
        if let task = tasks[id] {
            return task
        }
        // Search in children of all tasks
        for task in tasks.values {
            if let found = findTaskInChildren(id: id, node: task) {
                return found
            }
        }
        return nil
    }

    private func findTaskInChildren(id: String, node: TaskNode) -> TaskNode? {
        if node.id == id {
            return node
        }
        for child in node.children {
            if let found = findTaskInChildren(id: id, node: child) {
                return found
            }
        }
        return nil
    }

    fileprivate func pushInternal(
        taskID parentID: String,
        name: String,
        _ step: @escaping @Sendable (any TaskContext) async throws -> Void
    ) async throws {
        guard let parentTask = findTask(id: parentID) else { return }

        let childNode = TaskNode(name: name, parentID: parentTask.id)
        parentTask.addChild(childNode)

        let previousNodeID = currentNodeID
        currentNodeID = childNode.id

        childNode.status = .running

        await broadcastGraph()

        do {
            let nestedContext = TaskContextImpl(executor: self, taskID: childNode.id)
            try await step(nestedContext)
            childNode.status = .completed
            childNode.progress = 1.0
            childNode.completedAt = Date()
        } catch {
            if isCancellationError(error) {
                childNode.status = .cancelled
            } else {
                childNode.status = .failed(error)
            }
            // Propagate failure to parent if parent is still running
            if parentTask.status == .running {
                parentTask.status = .failed(error)
            }
            throw error
        }

        parentTask.recalculateProgress()
        currentNodeID = previousNodeID

        await broadcastGraph()

        // Schedule cleanup after visibility duration
        scheduleCleanup()
    }

    // MARK: - Stream Management

    private func registerContinuation(_ continuation: AsyncStream<TaskGraph>.Continuation, id: UUID) {
        streamContinuations[id] = continuation
    }

    private func unregisterContinuation(id: UUID) {
        streamContinuations.removeValue(forKey: id)
    }

    private func broadcastGraph() async {
        let graph = TaskGraph(tasks: allTasks.map { TaskSnapshot(from: $0) })
        for continuation in streamContinuations.values {
            continuation.yield(graph)
        }
    }

    private func cancelChildren(of node: TaskNode) {
        for child in node.children {
            if child.status.isRunning {
                child.status = .cancelled
            }
            cancelChildren(of: child)
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        error is CancellationError
    }
}

/// Represents the complete state of all tasks managed by a ``TaskExecutor``.
///
/// The task graph provides a consistent, immutable snapshot of the entire
/// task hierarchy at a point in time. This is useful for UI rendering or
/// logging where you need a stable view of the task state.
///
/// You receive ``TaskGraph`` instances through the ``TaskExecutor/progressStream``
/// async stream, which emits a new graph whenever any task state changes.
///
/// ```swift
/// for await graph in executor.progressStream {
///     print("Active tasks: \(graph.tasks.count)")
///     for task in graph.tasks {
///         print("  - \(task.name): \(task.progress ?? 0)%")
///     }
/// }
/// ```
public struct TaskGraph: Sendable {
    /// All tasks managed by the executor, sorted by creation time (oldest first).
    public let tasks: [TaskSnapshot]

    /// Creates a new task graph.
    /// - Parameter tasks: The tasks to include in the graph.
    public init(tasks: [TaskSnapshot]) {
        self.tasks = tasks
    }
}

/// A snapshot of a task node for UI rendering and state observation.
///
/// ``TaskSnapshot`` captures the state of a task at a specific moment in time.
/// Unlike ``TaskNode``, which is an internal mutable representation, snapshots
/// are immutable and safe to use from any thread.
///
/// Snapshots form a tree structure: each snapshot can have child snapshots
/// representing subtasks created with ``TaskContext/push(_:_:)``.
///
/// ## Thread Safety
///
/// All properties on ``TaskSnapshot`` are immutable, making it safe to access
/// from any thread without additional synchronization.
///
/// ## Equality
///
/// Two snapshots are considered equal if their progress-affecting fields match.
/// Use ``progressHash`` to detect changes in progress, and ``identityHash``
/// for set membership operations based on task identity alone.
public struct TaskSnapshot: Identifiable, Sendable, Equatable {
    /// The unique identifier for this task.
    ///
    /// This matches the ID passed to ``TaskExecutor/addTask(name:id:options:_:)``
    /// or auto-generated if not provided.
    public let id: String

    /// The display name for the task.
    public let name: String

    /// The current progress value, from 0.0 to 1.0.
    ///
    /// Returns `nil` if progress is indeterminate (task hasn't reported progress yet).
    /// Values are clamped to the valid range and never exceed 1.0.
    public let progress: Float?

    /// The current step name or phase description.
    ///
    /// This provides additional context about what the task is currently doing,
    /// such as "Downloading file 3 of 10" or "Parsing records...".
    public let stepName: String?

    /// The current execution status.
    public let status: TaskStatus

    /// The task's execution options.
    ///
    /// Indicates whether the task can be paused or cancelled.
    public let options: TaskOptions

    /// A Boolean value indicating whether the task is currently paused.
    public let isPaused: Bool

    /// Child task snapshots representing subtasks.
    ///
    /// These are created via ``TaskContext/push(_:_:)`` and are sorted
    /// by creation time (oldest first).
    public let children: [TaskSnapshot]

    /// The date when this task completed, or `nil` if not yet completed.
    public let completedAt: Date?

    /// The date when this task was created.
    ///
    /// Used for stable ordering of tasks in the UI.
    public let createdAt: Date

    /// A description of the error if the task failed, or `nil`.
    public let errorDescription: String?

    /// Creates a snapshot from a task node.
    /// - Parameter node: The task node to snapshot.
    public init(from node: TaskNode) {
        self.id = node.id
        self.name = node.name
        self.progress = node.progress
        self.stepName = node.stepName
        self.status = node.status
        self.options = node.options
        self.isPaused = node.isPaused
        self.children = node.children.map { TaskSnapshot(from: $0) }
        self.createdAt = node.createdAt
        self.errorDescription = Self.extractErrorDescription(from: node.status)

        // Record completion time if completed
        if case .completed = node.status {
            self.completedAt = Date()
        } else {
            self.completedAt = nil
        }
    }

    private static func extractErrorDescription(from status: TaskStatus) -> String? {
        if case .failed(let error) = status {
            // Try to get a clean error message
            let nsError = error as NSError
            if !nsError.localizedDescription.isEmpty && nsError.localizedDescription != nsError.domain {
                return nsError.localizedDescription
            }
            return nsError.domain
        }
        return nil
    }

    /// A Boolean value indicating whether the task completed successfully.
    public var isCompleted: Bool {
        if case .completed = status { return true }
        return false
    }

    /// A Boolean value indicating whether the task failed with an error.
    public var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    /// A Boolean value indicating whether the task is currently executing.
    public var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    /// A Boolean value indicating whether the task has any child subtasks.
    public var hasChildren: Bool {
        !children.isEmpty
    }

    /// Returns a hash value for all progress-affecting fields.
    ///
    /// Use this property to detect meaningful changes in progress state
    /// for UI update optimization. The hash includes:
    /// - Task identity (id, createdAt)
    /// - Progress value
    /// - Status
    /// - Pause state
    /// - Step name
    /// - Error description
    /// - All children's progress hashes
    ///
    /// If two snapshots have the same progressHash, they represent
    /// the same visual state.
    public var progressHash: Int {
        var hash = id.hashValue
        hash ^= createdAt.timeIntervalSince1970.hashValue
        if let progress = progress {
            hash ^= Int(progress * 1000)
        } else {
            hash ^= -1 // Indeterminate marker
        }
        hash ^= status.hashValue
        hash ^= isPaused.hashValue
        if let stepName = stepName {
            hash ^= stepName.hashValue
        }
        if let errorDescription = errorDescription {
            hash ^= errorDescription.hashValue
        }
        for child in children {
            hash ^= child.progressHash
        }
        return hash
    }

    /// Hash for set membership - considers only the task's identity.
    ///
    /// Unlike ``progressHash``, this only includes the task's ID, making it
    /// suitable for deduplication or tracking task identity in collections
    /// where you don't care about state changes.
    public var identityHash: Int {
        id.hashValue
    }

    public static func == (lhs: TaskSnapshot, rhs: TaskSnapshot) -> Bool {
        lhs.id == rhs.id
            && lhs.progress == rhs.progress
            && lhs.status == rhs.status
            && lhs.isPaused == rhs.isPaused
            && lhs.stepName == rhs.stepName
            && lhs.children == rhs.children
            && lhs.errorDescription == rhs.errorDescription
    }
}
