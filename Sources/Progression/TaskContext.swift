//
//  TaskContext.swift
//  Progression
//
//  Created by Mark Onyschuk on 1/13/26.
//  Copyright © 2026 by Dimension North Inc, All Rights Reserved.
//

/// Context provided to async tasks for reporting progress and creating subtasks.
///
/// The task context is the primary interface between your async functions
/// and the Progression system. Instances are passed to tasks during execution.
public protocol TaskContext: AnyObject, Sendable {
    /// Reports progress to the current task node.
    ///
    /// This method also checks for Swift Task cancellation, so calling
    /// `executor.cancel()` will cause this to throw `CancellationError`.
    ///
    /// - Parameter progress: The progress update to report
    /// - Throws: `CancellationError` if the task was cancelled
    func report(_ progress: TaskProgress) async throws

    /// Begins a nested subtask and awaits its completion.
    ///
    /// The subtask runs asynchronously and its progress is tracked
    /// as a child of the current task. The function waits for the
    /// subtask to complete before returning.
    ///
    /// - Parameters:
    ///   - name: Display name for the subtask
    ///   - step: The async function to execute for this subtask
    /// - Throws: Re-throws any error from the subtask function
    func push(_ name: String, _ step: @escaping @Sendable (any TaskContext) async throws -> Void) async throws
}
