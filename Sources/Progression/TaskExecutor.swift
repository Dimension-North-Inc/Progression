//
//  TaskExecutor.swift
//  Progression
//
//  Created by Mark Onyschuk on 1/13/26.
//  Copyright © 2026 by Dimension North Inc, All Rights Reserved.
//

import Foundation

/// Internal implementation of TaskContext that delegates to the executor actor.
final class TaskContextImpl: @unchecked Sendable, TaskContext {
    private weak let executor: TaskExecutor?
    private let taskID: UUID

    init(executor: TaskExecutor, taskID: UUID) {
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
    private var tasks: [UUID: TaskNode] = [:]
    private var currentNodeID: UUID?

    private var pauseContinuations: [UUID: CheckedContinuation<Void, Never>] = [:]
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
    /// - Parameter name: Display name for the task
    /// - Parameter options: Task execution options (cancellable, pausable)
    /// - Parameter task: The async task to execute
    /// - Returns: The ID of the added task
    @discardableResult
    public func addTask(
        name: String,
        options: TaskOptions = .default,
        _ task: @escaping @Sendable (any TaskContext) async throws -> Void
    ) async -> UUID {
        let taskNode = TaskNode(name: name, options: options)
        taskNode.status = .running
        tasks[taskNode.id] = taskNode

        let taskID = taskNode.id
        currentNodeID = taskID

        // Broadcast initial state
        await broadcastGraph()

        // Run the task in background
        Task {
            let context = TaskContextImpl(executor: self, taskID: taskID)
            do {
                try await task(context)
                taskNode.status = .completed
                taskNode.progress = 1.0
                taskNode.completedAt = Date()
            } catch {
                if isCancellationError(error) {
                    taskNode.status = .cancelled
                } else {
                    taskNode.status = .failed(error)
                }
            }
            currentNodeID = nil
            await broadcastGraph()

            // Schedule cleanup after visibility duration
            scheduleCleanup()
        }

        return taskID
    }

    /// Pauses a specific task and all its children.
    public func pause(taskID: UUID) {
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
    public func resume(taskID: UUID) {
        guard let task = tasks[taskID] else { return }
        resumeRecursive(task)
        Task { await broadcastGraph() }
    }

    private func resumeRecursive(_ node: TaskNode) {
        node.resume()
        // Resume any waiting continuation for this node
        if let continuation = pauseContinuations.removeValue(forKey: node.id) {
            continuation.resume()
        }
        for child in node.children {
            resumeRecursive(child)
        }
    }

    /// Cancels a specific task.
    public func cancel(taskID: UUID) {
        guard let task = tasks[taskID], task.options.isCancellable else { return }

        task.status = .cancelled
        task.isPaused = false
        cancelChildren(of: task)

        // Only resume waiting tasks if this was the one waiting
        if let continuation = pauseContinuations.removeValue(forKey: taskID) {
            continuation.resume()
        }

        Task { await broadcastGraph() }

        // Schedule removal after brief visibility
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            // Only remove if still cancelled (not restarted)
            if case .cancelled = task.status {
                tasks.removeValue(forKey: taskID)
                await broadcastGraph()
            }
        }
    }

    /// Removes a failed or completed task immediately.
    public func remove(taskID: UUID) {
        guard let task = tasks[taskID] else { return }

        // Mark as cancelled
        task.status = .cancelled
        task.isPaused = false
        cancelChildren(of: task)

        // Only resume waiting tasks if this was the one waiting
        if let continuation = pauseContinuations.removeValue(forKey: taskID) {
            continuation.resume()
        }

        // Remove immediately
        tasks.removeValue(forKey: taskID)
        Task { await broadcastGraph() }
    }

    /// Cancels all tasks.
    public func cancelAll() {
        for task in tasks.values {
            if task.options.isCancellable {
                task.status = .cancelled
                task.isPaused = false
                cancelChildren(of: task)
            }
        }
        resumeWaitingTasks()
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

    fileprivate func reportInternal(taskID: UUID, _ progress: TaskProgress) async throws {
        guard let task = findTask(id: taskID) else { return }

        // Check if cancelled
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
    private func findTask(id: UUID) -> TaskNode? {
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

    private func findTaskInChildren(id: UUID, node: TaskNode) -> TaskNode? {
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
        taskID parentID: UUID,
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

    private func resumeWaitingTasks() {
        for (_, continuation) in pauseContinuations {
            continuation.resume()
        }
        pauseContinuations.removeAll()
    }

    private func isCancellationError(_ error: Error) -> Bool {
        error is CancellationError
    }
}

/// Represents the complete task graph state.
public struct TaskGraph: Sendable {
    public let tasks: [TaskSnapshot]

    public init(tasks: [TaskSnapshot]) {
        self.tasks = tasks
    }
}

/// A snapshot of a task node for the UI.
public struct TaskSnapshot: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let progress: Float?
    public let stepName: String?
    public let status: TaskStatus
    public let options: TaskOptions
    public let isPaused: Bool
    public let children: [TaskSnapshot]
    public let completedAt: Date?
    public let createdAt: Date
    public let errorDescription: String?

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

    public var isCompleted: Bool {
        if case .completed = status { return true }
        return false
    }

    public var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    public var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    public var hasChildren: Bool {
        !children.isEmpty
    }

    /// Returns a hash value for all progress-affecting fields.
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

    /// Hash for set membership - only considers the node's identity
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
