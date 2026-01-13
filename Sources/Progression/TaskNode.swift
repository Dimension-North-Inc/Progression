//
//  TaskNode.swift
//  Progression
//
//  Created by Mark Onyschuk on 1/13/26.
//  Copyright © 2026 by Dimension North Inc, All Rights Reserved.
//

import Foundation

/// Represents a node in the task tree hierarchy.
///
/// Task nodes are created internally by ``TaskExecutor`` and are not
/// typically created directly. Use ``TaskExecutor/addTask(name:options:_:)``
/// to create tasks.
///
/// A task node can have child nodes, representing subtasks. Child nodes
/// are managed through the ``addChild(_:)`` method.
public final class TaskNode: @unchecked Sendable, Identifiable {
    /// The unique identifier for this task.
    public let id: UUID

    /// The display name for the task.
    public var name: String

    /// Thread lock for property access.
    private let lock = NSLock()

    /// The parent node's ID, if any.
    private let parentID: UUID?

    /// Child task nodes.
    private var _children: [TaskNode]

    /// Progress value from 0.0 to 1.0, or nil for indeterminate.
    private var _progress: Float?

    /// Current step name or phase description.
    private var _stepName: String?

    /// Execution status.
    private var _status: TaskStatus

    /// UI expansion state.
    private var _isExpanded: Bool

    /// Task execution options.
    private var _options: TaskOptions

    /// Pause state.
    private var _isPaused: Bool

    /// Creation timestamp.
    private let _createdAt = Date()

    /// Completion timestamp.
    private var _completedAt: Date?

    /// The parent node, if any.
    public unowned var parent: TaskNode?

    /// Creates a new task node.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this node. A new UUID is generated if not provided.
    ///   - name: Display name for the task.
    ///   - parentID: Optional parent node ID for hierarchical tracking.
    ///   - options: Task execution options. Uses ``TaskOptions/default`` by default.
    public init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        options: TaskOptions = .default
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self._children = []
        self._progress = nil
        self._status = .pending
        self._isExpanded = true
        self._options = options
        self._isPaused = false
        self._completedAt = nil
    }

    // MARK: - Timestamps

    /// The date when this task was created.
    ///
    /// Used for stable ordering of tasks and children.
    public var createdAt: Date {
        lock.lock()
        defer { lock.unlock() }
        return _createdAt
    }

    // MARK: - Child Management

    /// The child nodes of this task.
    ///
    /// Returns a snapshot of the current children array. The array is
    /// thread-safe for read operations.
    public var children: [TaskNode] {
        lock.lock()
        defer { lock.unlock() }
        return _children
    }

    /// Adds a child node to this task.
    ///
    /// The child node's parent reference is updated to point to this node.
    /// Children are kept sorted by creation time (oldest first).
    ///
    /// - Parameter child: The child node to add.
    public func addChild(_ child: TaskNode) {
        lock.lock()
        defer { lock.unlock() }
        child.parent = self
        _children.append(child)
        _children.sort { lhs, rhs in
            lhs.createdAt < rhs.createdAt
        }
    }

    /// Removes all child nodes.
    ///
    /// Each child's parent reference is set to nil before removal.
    public func removeAllChildren() {
        lock.lock()
        defer { lock.unlock() }
        for child in _children {
            child.parent = nil
        }
        _children.removeAll()
    }

    // MARK: - Progress

    /// The current progress value.
    ///
    /// A value between 0.0 and 1.0 representing completion percentage,
    /// or `nil` if the progress is indeterminate (not yet started or unknown).
    ///
    /// Setting this value clamps the input to the valid range 0.0...1.0.
    public var progress: Float? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _progress
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            if let value = newValue {
                _progress = max(0.0, min(1.0, value))
            } else {
                _progress = nil
            }
        }
    }

    /// The current step name or phase description.
    ///
    /// This provides additional context about what the task is currently doing.
    /// For example: "Downloading file 3 of 10" or "Parsing records..."
    public var stepName: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _stepName
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _stepName = newValue
        }
    }

    // MARK: - Status

    /// The current execution status.
    ///
    /// See ``TaskStatus`` for possible values.
    public var status: TaskStatus {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _status
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _status = newValue
        }
    }

    // MARK: - UI State

    /// A Boolean value that indicates whether this node's children are expanded in the UI.
    ///
    /// This property is not currently used by the standard UI components,
    /// but is available for custom implementations.
    public var isExpanded: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isExpanded
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isExpanded = newValue
        }
    }

    /// Toggles the expanded state.
    public func toggleExpanded() {
        lock.lock()
        defer { lock.unlock() }
        _isExpanded.toggle()
    }

    // MARK: - Task Options

    /// The execution options for this task.
    ///
    /// Controls whether the task can be cancelled or paused.
    public var options: TaskOptions {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _options
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _options = newValue
        }
    }

    // MARK: - Pause State

    /// A Boolean value that indicates whether this task is currently paused.
    public var isPaused: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isPaused
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isPaused = newValue
        }
    }

    /// Pauses this task.
    ///
    /// When paused, progress reporting will block until the task is resumed.
    /// This affects this node only; use ``TaskExecutor/pause(taskID:)`` to
    /// pause a task and all its children.
    public func pause() {
        lock.lock()
        defer { lock.unlock() }
        _isPaused = true
    }

    /// Resumes this task.
    ///
    /// If the task was waiting on a paused continuation, it will proceed.
    /// This affects this node only; use ``TaskExecutor/resume(taskID:)`` to
    /// resume a task and all its children.
    public func resume() {
        lock.lock()
        defer { lock.unlock() }
        _isPaused = false
    }

    // MARK: - Completion Time

    /// The date when this task completed, or nil if not yet completed.
    public var completedAt: Date? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _completedAt
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _completedAt = newValue
        }
    }

    /// Removes children that have been completed longer than the visibility duration.
    ///
    /// - Parameter cutoff: The cutoff timestamp - children completed before this are removed.
    public func cleanupCompletedChildren(olderThan cutoff: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }

        _children = _children.filter { child in
            // Keep running children
            if child.isRunning { return true }
            // Keep non-completed children (failed, cancelled)
            if !child.isCompleted { return true }
            // Keep if completed recently
            if let completedAt = child.completedAt {
                return completedAt.timeIntervalSince1970 >= cutoff
            }
            return true
        }
    }

    // MARK: - Computed Properties

    /// A Boolean value that indicates whether this task has any child tasks.
    public var hasChildren: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !_children.isEmpty
    }

    /// Recalculates progress based on children's progress.
    ///
    /// The parent task's progress is calculated as the average of all
    /// children's progress. If any child is indeterminate (nil progress),
    /// the parent also becomes indeterminate.
    ///
    /// This method is called automatically by ``TaskExecutor`` when
    /// subtasks complete, but is also available for manual use.
    public func recalculateProgress() {
        lock.lock()
        defer { lock.unlock() }

        guard !_children.isEmpty else { return }

        var totalWeight: Float = 0
        var weightedProgress: Float = 0
        var allChildrenIndeterminate = true

        for child in _children {
            let weight: Float = 1.0
            totalWeight += weight
            if let childProgress = child.progress {
                weightedProgress += childProgress * weight
                allChildrenIndeterminate = false
            } else {
                // Treat indeterminate child as 0% progress
                weightedProgress += 0
            }
        }

        // Parent is indeterminate only if ALL children are still indeterminate
        if allChildrenIndeterminate {
            _progress = nil
        } else {
            _progress = totalWeight > 0 ? weightedProgress / totalWeight : 0
        }
    }

    /// A Boolean value that indicates whether this task is completed.
    public var isCompleted: Bool {
        if case .completed = _status { return true }
        return false
    }

    /// A Boolean value that indicates whether this task is currently running.
    public var isRunning: Bool {
        if case .running = _status { return true }
        return false
    }
}

/// Possible states for a task node.
///
/// ```swift
/// switch status {
/// case .pending:
///     print("Task has not started")
/// case .running:
///     print("Task is executing")
/// case .completed:
///     print("Task finished successfully")
/// case .failed(let error):
///     print("Task failed: \(error)")
/// case .cancelled:
///     print("Task was cancelled")
/// }
/// ```
public enum TaskStatus: Sendable, Equatable, Hashable {
    /// Task has not yet started.
    case pending

    /// Task is currently executing.
    case running

    /// Task completed successfully.
    case completed

    /// Task failed with an error.
    case failed(any Error)

    /// Task was cancelled before completion.
    case cancelled

    /// A Boolean value that indicates whether this status represents a running state.
    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public static func == (lhs: TaskStatus, rhs: TaskStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending):
            return true
        case (.running, .running):
            return true
        case (.completed, .completed):
            return true
        case (.cancelled, .cancelled):
            return true

        case (.failed(let lhsError), .failed(let rhsError)):
            // Compare error strings for simplicity
            return String(describing: lhsError) == String(describing: rhsError)

        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .pending:
            hasher.combine(0)
        case .running:
            hasher.combine(1)
        case .completed:
            hasher.combine(2)
        case .cancelled:
            hasher.combine(3)
        case .failed:
            hasher.combine(4)
        }
    }
}
