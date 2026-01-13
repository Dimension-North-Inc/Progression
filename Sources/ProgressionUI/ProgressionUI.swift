//
//  ProgressionUI.swift
//  Progression
//
//  Created by Mark Onyschuk on 1/13/26.
//  Copyright © 2026 by Dimension North Inc, All Rights Reserved.
//

/// ProgressionUI provides SwiftUI views for displaying task progress.
@_exported import SwiftUI
@_exported import Progression

// MARK: - Localized Progress Support

/// Represents progress with localized string keys for internationalization.
///
/// This mirrors the approach from the old Dream Vault code, providing
/// `LocalizedStringKey` support for i18n-ready progress reporting.
public struct LocalizedProgress: Equatable {
    /// The localized step name.
    public var name: LocalizedStringKey

    /// The numerical progress value, or nil for indeterminate.
    public var completeness: Float?

    /// Creates a named progress update.
    public static func named(_ name: LocalizedStringKey) -> Self {
        LocalizedProgress(name: name, completeness: nil)
    }

    /// Creates a numerical progress update with a localized name.
    public static func progress(_ value: Float, named name: LocalizedStringKey? = nil) -> Self {
        LocalizedProgress(name: name ?? "Processing", completeness: value)
    }

    /// Creates a step-based progress update with a localized name.
    public static func step(_ current: Int, of total: Int, named name: LocalizedStringKey? = nil) -> Self {
        let progress = total > 0 ? Float(current) / Float(total) : 0
        return LocalizedProgress(name: name ?? "Processing", completeness: progress)
    }

    /// Creates a completed progress indicator.
    public static var completed: Self {
        LocalizedProgress(name: "Complete", completeness: 1.0)
    }
}

extension TaskProgress {
    /// Creates a progress from a localized progress description.
    /// The LocalizedStringKey is converted to a string key for storage.
    public static func from(_ localized: LocalizedProgress) -> Self {
        let name = String(describing: localized.name)
        if let completeness = localized.completeness {
            return TaskProgress(name: name, completeness: completeness)
        }
        return TaskProgress.named(name)
    }
}

extension TaskContext {
    /// Reports progress with a localized string key.
    ///
    /// ```swift
    /// try await context.reportLocalized(.named("Connecting..."))
    /// try await context.reportLocalized(.progress(0.5, named: "Downloading..."))
    /// ```
    public func reportLocalized(_ progress: LocalizedProgress) async throws {
        try await report(TaskProgress.from(progress))
    }
}

// MARK: - Progress Modifiers

extension LocalizedProgress {
    /// Returns a new progress with an updated name.
    public func renamed(to name: LocalizedStringKey) -> Self {
        LocalizedProgress(name: name, completeness: completeness)
    }

    /// Returns a new progress with an updated progress value.
    public func advanced(to value: Float) -> Self {
        let clamped = min(max(value, 0.0), 1.0)
        return LocalizedProgress(name: name, completeness: clamped)
    }

    /// Returns a new progress from step count.
    public func advanced(to step: Int, of total: Int) -> Self {
        guard total > 0 else { return advanced(to: 0) }
        let clampedStep = min(step, total)
        let progress = Float(clampedStep) / Float(total)
        return advanced(to: progress)
    }
}
