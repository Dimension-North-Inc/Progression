//
//  ProgressionError.swift
//  Progression
//
//  Created by Mark Onyschuk on 1/13/26.
//  Copyright © 2026 by Dimension North Inc, All Rights Reserved.
//

/// Errors that can occur during task execution.
///
/// ```swift
/// do {
///     try await context.push("Risky Task") { subContext in
///         try await riskyFunction()
///     }
/// } catch ProgressionError.cancelled {
///     print("Task was cancelled")
/// } catch ProgressionError.subtaskFailed(let error) {
///     print("Subtask failed: \(error)")
/// } catch ProgressionError.invalidProgressValue(let value) {
///     print("Invalid progress: \(value)")
/// }
/// ```
public enum ProgressionError: Error, Sendable, Equatable {
    /// The task was cancelled before completion.
    case cancelled

    /// A subtask failed with the underlying error.
    case subtaskFailed(underlying: any Error)

    /// Attempted to report progress outside valid bounds.
    case invalidProgressValue(Float)

    public static func == (lhs: ProgressionError, rhs: ProgressionError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled):
            return true
        case (.invalidProgressValue(let a), .invalidProgressValue(let b)):
            return a == b
        case (.subtaskFailed, .subtaskFailed):
            // We can't compare errors by value, but Sendable enums with
            // associated values still work in Sendable contexts
            return true
        default:
            return false
        }
    }
}
