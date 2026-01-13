//
//  Progress.swift
//  Progression
//
//  Created by Mark Onyschuk on 1/13/26.
//  Copyright © 2026 by Dimension North Inc, All Rights Reserved.
//

/// Represents progress updates from a long-running task.
///
/// Progress can be named, numerical, or a combination of both.
/// Use the static factory methods as starting points, then modify
/// incrementally using the instance methods.
///
/// ## Example
///
/// ```swift
/// // Named step only
/// try await context.report(.named("Downloading..."))
///
/// // Numerical progress
/// try await context.report(.progress(0.5))
///
/// // Combined
/// try await context.report(.named("Step 3").progress(0.75))
/// ```
public struct TaskProgress: Sendable {
    /// The name of the current step or phase.
    public var name: String

    /// The numerical progress value, from 0.0 to 1.0.
    /// nil indicates an indeterminate (unknown) progress.
    public var completeness: Float?

    /// Creates a new progress with a name and optional completeness.
    public init(name: String, completeness: Float? = nil) {
        self.name = name
        self.completeness = completeness
    }

    // MARK: - Static Factories

    /// Creates a named progress update without a numerical value.
    /// Useful for indicating a step name or phase.
    public static func named(_ name: String) -> Self {
        TaskProgress(name: name, completeness: nil)
    }

    /// Creates a numerical progress update with a default name.
    public static func progress(_ value: Float) -> Self {
        TaskProgress(name: "Processing", completeness: value)
    }

    /// Creates a step-based progress update.
    /// Automatically calculates completeness as current/total.
    public static func step(_ current: Int, of total: Int) -> Self {
        TaskProgress(name: "Processing", completeness: Float(current) / Float(total))
    }

    // MARK: - Instance Modifiers

    /// Returns a new progress with the specified name, preserving completeness.
    public func named(_ name: String) -> Self {
        TaskProgress(name: name, completeness: completeness)
    }

    /// Returns a new progress with the specified completeness, preserving name.
    public func progress(_ value: Float) -> Self {
        TaskProgress(name: self.name, completeness: value)
    }

    /// Returns a new progress with calculated completeness from step count.
    public func step(_ current: Int, of total: Int) -> Self {
        TaskProgress(name: self.name, completeness: Float(current) / Float(total))
    }

    // MARK: - Helpers

    /// Returns a progress indicating the task is complete.
    public static var completed: Self {
        TaskProgress(name: "Complete", completeness: 1.0)
    }

    /// Returns an indeterminate progress (no numerical value).
    public static func indeterminate(named name: String = "Processing") -> Self {
        TaskProgress(name: name, completeness: nil)
    }

    /// Whether this progress has a numerical completeness value.
    public var isIndeterminate: Bool { completeness == nil }

    /// Whether this progress indicates completion.
    /// Only true for explicitly completed progress (name is "Complete").
    public var isComplete: Bool { name == "Complete" && completeness == 1.0 }

    /// The completeness value clamped to 0.0...1.0, or nil if indeterminate.
    public var clampedCompleteness: Float? {
        guard let completeness else { return nil }
        return max(0.0, min(1.0, completeness))
    }
}

/// Backwards compatibility type alias.
@available(*, deprecated, renamed: "TaskProgress")
public typealias Progress = TaskProgress
