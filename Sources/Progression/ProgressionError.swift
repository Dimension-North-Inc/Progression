//
//  ProgressionError.swift
//  Progression
//
//  Created by Mark Onyschuk on 1/13/26.
//  Copyright © 2026 by Dimension North Inc, All Rights Reserved.
//

import Foundation

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
public enum ProgressionError: Error, Sendable, Equatable, LocalizedError {
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

    /// A localized message describing the error.
    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return NSLocalizedString(
                "error.cancelled",
                tableName: "Errors",
                bundle: .module,
                value: "Task was cancelled",
                comment: "Cancellation error message"
            )

        case .subtaskFailed(let error):
            let template = NSLocalizedString(
                "error.subtaskFailed",
                tableName: "Errors",
                bundle: .module,
                value: "Subtask failed: %@",
                comment: "Subtask failed with underlying error"
            )
            if let localizedError = error as? LocalizedError,
               let description = localizedError.errorDescription {
                return String(format: template, description)
            }
            return NSLocalizedString(
                "error.subtaskFailed.generic",
                tableName: "Errors",
                bundle: .module,
                value: "Subtask failed",
                comment: "Subtask failed without underlying error details"
            )

        case .invalidProgressValue:
            return NSLocalizedString(
                "error.invalidProgressValue",
                tableName: "Errors",
                bundle: .module,
                value: "Invalid progress value",
                comment: "Invalid progress value error"
            )
        }
    }
}

/// Error thrown when a task exceeds its configured timeout.
///
/// Catch this error to handle timeout scenarios:
///
/// ```swift
/// do {
///     try await context.push("Network Request") { _ in
///         // This task has a 30 second timeout
///         try await fetchData()
///     }
/// } catch is TaskTimeoutError {
///     print("Request timed out")
/// }
/// ```
public struct TaskTimeoutError: Error, Sendable, Equatable, LocalizedError {
    /// The ID of the task that timed out.
    public let taskID: String

    /// The configured timeout duration.
    public let timeout: Duration

    /// Creates a new timeout error.
    /// - Parameters:
    ///   - taskID: The ID of the timed-out task.
    ///   - timeout: The configured timeout duration.
    public init(taskID: String, timeout: Duration) {
        self.taskID = taskID
        self.timeout = timeout
    }

    /// A localized message describing the error.
    public var errorDescription: String? {
        // Use FormatStyle's Duration.UnitsFormatStyle for modern, locale-aware formatting
        let durationString = timeout.formatted(.units(allowed: [.seconds, .minutes, .hours], width: .wide))
        let template = NSLocalizedString(
            "error.timeout",
            tableName: "Errors",
            bundle: .module,
            value: "Task timed out after %@",
            comment: "Timeout error message"
        )
        return String(format: template, durationString)
    }
}
