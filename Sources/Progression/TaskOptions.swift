/// Configuration options for task execution.
///
/// Use the static factory methods to create common configurations,
/// or create custom options using the initializer.
///
/// ## Example
///
/// ```swift
/// // Default: cancellable, not pausable
/// let task1 = TaskOptions.default
///
/// // Fully interactive
/// let task2 = TaskOptions.interactive
///
/// // Custom
/// let task3 = TaskOptions(isCancellable: true, isPausable: true)
/// ```
public struct TaskOptions: Sendable, Equatable {
    /// A Boolean value that indicates whether the task can be cancelled.
    ///
    /// When `true`, the task can be stopped by calling ``TaskExecutor/cancel(taskID:)``.
    /// When `false`, calls to cancel will be ignored.
    public var isCancellable: Bool

    /// A Boolean value that indicates whether the task can be paused and resumed.
    ///
    /// When `true`, the task can be paused by calling ``TaskExecutor/pause(taskID:)``
    /// and resumed by calling ``TaskExecutor/resume(taskID:)``.
    /// When `false`, pause/resume operations will be ignored.
    public var isPausable: Bool

    /// Creates a new task options configuration.
    /// - Parameters:
    ///   - isCancellable: Whether the task supports cancellation. Default is `true`.
    ///   - isPausable: Whether the task supports pausing and resuming. Default is `false`.
    public init(
        isCancellable: Bool = true,
        isPausable: Bool = false
    ) {
        self.isCancellable = isCancellable
        self.isPausable = isPausable
    }

    /// Default options for a standard task.
    ///
    /// The task can be cancelled but cannot be paused.
    /// This is appropriate for most background operations.
    public static var `default`: Self {
        TaskOptions(isCancellable: true, isPausable: false)
    }

    /// Options for a task that cannot be cancelled or paused.
    ///
    /// Use this for critical operations that must complete.
    public static var immutable: Self {
        TaskOptions(isCancellable: false, isPausable: false)
    }

    /// Options for a fully interactive task.
    ///
    /// The task can be both cancelled and paused.
    /// Use this when you want the user to have full control.
    public static var interactive: Self {
        TaskOptions(isCancellable: true, isPausable: true)
    }
}
