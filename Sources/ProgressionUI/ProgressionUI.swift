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

// MARK: - URLSession Extensions

/// Extension providing URLSession methods that report progress to a TaskContext.
extension URLSession {
    /// Performs a data task and reports progress to the task context.
    ///
    /// This method wraps `data(for:)` with automatic progress reporting.
    /// Progress is reported as:
    /// - Named step "Connecting..." when starting
    /// - Named step "Downloading..." when data is received
    /// - Named step "Complete" when finished
    ///
    /// ```swift
    /// await executor.addTask(name: "Fetch Data") { context in
    ///     let (data, response) = try await context.urlSession.data(for: urlRequest)
    /// }
    /// ```
    ///
    /// - Parameter request: The URL request to execute
    /// - Returns: The downloaded data and response
    /// - Throws: Any error from the request, or `CancellationError` if task is cancelled
    public func data(
        for request: URLRequest,
        using context: any TaskContext
    ) async throws -> (Data, URLResponse) {
        let (data, response) = try await self.data(for: request)

        try await context.push("Download") { downloadContext in
            try await downloadContext.report(.named("Connecting..."))
            try await downloadContext.report(.named("Downloading..."))
            try await downloadContext.report(.completed)
        }

        return (data, response)
    }

    /// Downloads a file and reports progress to the task context.
    ///
    /// The download location is provided by the system's temporary directory.
    ///
    /// ```swift
    /// await executor.addTask(name: "Download File") { context in
    ///     let localURL = try await context.urlSession.download(for: request)
    ///     // Move the file from localURL to your desired location
    /// }
    /// ```
    ///
    /// - Parameter request: The URL request to execute
    /// - Parameter context: The task context for progress reporting
    /// - Returns: The temporary file URL of the downloaded file
    /// - Throws: Any error from the download, or `CancellationError` if task is cancelled
    public func download(
        for request: URLRequest,
        using context: any TaskContext
    ) async throws -> URL {
        let (temporaryURL, _) = try await self.download(for: request)

        try await context.push("Download") { downloadContext in
            try await downloadContext.report(.named("Connecting..."))
            try await downloadContext.report(.named("Download complete"))
            try await downloadContext.report(.completed)
        }

        return temporaryURL
    }
}

// MARK: - TaskContext Convenience Methods

extension TaskContext {
    /// Performs a URL request and reports progress.
    ///
    /// A convenience method that uses a shared URLSession to fetch data.
    ///
    /// ```swift
    /// await executor.addTask(name: "Fetch API") { context in
    ///     let (data, response) = try await context.fetch(url: myURL)
    /// }
    /// ```
    ///
    /// - Parameter url: The URL to fetch
    /// - Returns: The downloaded data and URL response
    /// - Throws: Any error from the request, or `CancellationError` if task is cancelled
    public func fetch(url: URL) async throws -> (Data, URLResponse) {
        let request = URLRequest(url: url)
        return try await URLSession.shared.data(for: request, using: self)
    }

    /// Performs a URL request with progress reporting.
    ///
    /// - Parameter request: The URL request to execute
    /// - Returns: The downloaded data and URL response
    /// - Throws: Any error from the request, or `CancellationError` if task is cancelled
    public func fetch(request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request, using: self)
    }

    /// Downloads a file with progress reporting.
    ///
    /// - Parameter url: The URL to download
    /// - Returns: The temporary file URL of the downloaded file
    /// - Throws: Any error from the download, or `CancellationError` if task is cancelled
    public func download(url: URL) async throws -> URL {
        let request = URLRequest(url: url)
        return try await URLSession.shared.download(for: request, using: self)
    }
}

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
