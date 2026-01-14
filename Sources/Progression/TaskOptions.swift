//
//  TaskOptions.swift
//  Progression
//
//  Created by Mark Onyschuk on 1/13/26.
//  Copyright © 2026 by Dimension North Inc, All Rights Reserved.
//

/// Configuration options for task execution.
///
/// Use the static factory methods to create common configurations,
/// or create custom options using the initializer or fluent methods.
///
/// ## Example
///
/// ```swift
/// // Default: cancellable, not pausable
/// let task1 = TaskOptions.default
///
/// // Fully interactive with timeout
/// let task2 = TaskOptions.interactive.timeout(.seconds(30))
///
/// // Custom with fluent API
/// let task3 = TaskOptions.default
///     .cancellable()
///     .timeout(.minutes(5))
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

    /// The maximum duration the task is allowed to execute.
    ///
    /// When the task exceeds this duration, it will be cancelled with a
    /// ``TaskTimeoutError``. Use ``Duration`` for natural time expressions:
    /// - `.seconds(30)`
    /// - `.minutes(5)`
    /// - `.milliseconds(500)`
    ///
    /// A value of `nil` means no timeout (default behavior).
    public var timeout: Duration?

    /// Creates a new task options configuration.
    /// - Parameters:
    ///   - isCancellable: Whether the task supports cancellation. Default is `true`.
    ///   - isPausable: Whether the task supports pausing and resuming. Default is `false`.
    ///   - timeout: Optional maximum execution duration.
    public init(
        isCancellable: Bool = true,
        isPausable: Bool = false,
        timeout: Duration? = nil
    ) {
        self.isCancellable = isCancellable
        self.isPausable = isPausable
        self.timeout = timeout
    }

    // MARK: - Fluent API

    /// Returns a new options configuration with the specified cancellable setting.
    ///
    /// - Parameter value: Whether the task should be cancellable. Default is `true`.
    /// - Returns: A new ``TaskOptions`` with the updated cancellable setting.
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public func cancellable(_ value: Bool = true) -> Self {
        TaskOptions(
            isCancellable: value,
            isPausable: isPausable,
            timeout: timeout
        )
    }

    /// Returns a new options configuration with the specified pausable setting.
    ///
    /// - Parameter value: Whether the task should be pausable. Default is `true`.
    /// - Returns: A new ``TaskOptions`` with the updated pausable setting.
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public func pausable(_ value: Bool = true) -> Self {
        TaskOptions(
            isCancellable: isCancellable,
            isPausable: value,
            timeout: timeout
        )
    }

    /// Returns a new options configuration with the specified timeout.
    ///
    /// - Parameter duration: The maximum execution duration. Use ``Duration``
    ///   for natural time expressions like `30.seconds` or `.minutes(5)`.
    /// - Returns: A new ``TaskOptions`` with the updated timeout.
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public func timeout(_ duration: Duration) -> Self {
        TaskOptions(
            isCancellable: isCancellable,
            isPausable: isPausable,
            timeout: duration
        )
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
