# Progression: Hierarchical Task Execution for Swift

[![Swift Version](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%2015.0+%7C%20iOS%2018.0+-blue.svg)](https://developer.apple.com/swift/)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](https://opensource.org/licenses/MIT)

**Progression** is a type-safe, actor-based Swift package for managing hierarchical task execution with progress tracking, cooperative cancellation, and pause/resume support.

## Key Features

- **Hierarchical Tasks** - Tasks can have nested subtasks with automatic progress aggregation
- **Progress Reporting** - Report named steps and numerical progress (0.0 to 1.0)
- **Cooperative Cancellation** - Leverages Swift's native Task cancellation model
- **Pause/Resume** - Pause tasks and all their children simultaneously
- **Error Propagation** - Errors in subtasks propagate to parent tasks
- **SwiftUI Integration** - Ready-to-use views for displaying task progress

## Core Concept

The central types are ``TaskExecutor`` (an actor that manages all tasks) and ``TaskContext`` (passed to your task functions for progress reporting). Tasks can have nested subtasks via ``TaskContext/push(_:_:)``, and progress is automatically aggregated from children to parents.

## Installation

### Swift Package Manager

Add Progression to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/Progression.git", from: "1.0.0")
]
```

Or in Xcode:
1. File → Add Package Dependency
2. Enter the repository URL
3. Add to your target

## Quick Start

```swift
import Progression

let executor = TaskExecutor()

// Start a task with progress reporting
await executor.addTask(name: "Data Import", options: .interactive) { context in
    // Report a named step
    try await context.report(.named("Initializing..."))
    try await Task.sleep(for: .seconds(1))

    // Report numerical progress
    try await context.report(.progress(0.2))

    // Create a subtask
    try await context.push("Downloading files") { downloadContext in
        for i in 1...10 {
            try await Task.sleep(for: .milliseconds(100))
            try await downloadContext.report(.progress(Double(i) / 10.0))
        }
    }

    // Report completion
    try await context.report(.progress(1.0))
}
```

## Task Author's Guide

### Cancellation

Progression uses Swift's native **cooperative cancellation** model. When a user cancels a task, the underlying Swift Task is cancelled, and your code can detect this in two ways:

**Option 1: Use `report()` (recommended)**

The `report()` method automatically checks for cancellation and throws `CancellationError` if the task was cancelled:

```swift
for file in files {
    try await context.report(.progress(Double(i) / Double(total)))
    process(file)  // Won't run if cancelled
}
```

**Option 2: Manual check**

Use Swift's native `Task.checkCancellation()` for work that doesn't otherwise report progress:

```swift
for file in files {
    try Task.checkCancellation()  // Throws if cancelled
    process(file)
}

// Or check directly:
for file in files {
    if Task.isCancelled { break }
    process(file)
}
```

**Best Practices**

- Always check for cancellation during long-running work
- Use `report()` frequently - it automatically checks cancellation
- Use `push()` for subtasks - gives you hierarchical progress tracking
- Catch errors from `push()` - child errors propagate to parent

**What NOT to Do**

```swift
// BAD: Long operation without cancellation check
for i in 1...10000 {
    heavyComputation()  // Cannot be cancelled!
}

// GOOD: Check periodically
for i in 1...10000 {
    if i % 100 == 0 { try Task.checkCancellation() }
    heavyComputation()
}
```

## Pre-built Task Steps

ProgressionUI provides convenient extensions for common async operations like network requests. These automatically create subtasks with progress reporting.

### URLSession Extensions

Fetch data or download files with automatic progress tracking:

```swift
// Simple fetch from URL
let (data, response) = try await context.fetch(url: myURL)

// Fetch with custom request
var request = URLRequest(url: myURL)
request.setValue("application/json", forHTTPHeaderField: "Accept")
let (data, response) = try await context.fetch(request: request)

// Download a file to temporary location
let localURL = try await context.download(url: fileURL)
```

Each network operation creates a "Download" subtask that reports:
- "Connecting..." when starting
- "Downloading..." when data is received
- "Complete" when finished

For more control, use the URLSession extensions directly:

```swift
// URLSession.data(for:using:) with progress
let (data, response) = try await URLSession.shared.data(for: request, using: context)

// URLSession.download(for:using:) with progress
let (tempURL, _) = try await URLSession.shared.download(for: request, using: context)
```

## Concepts

### TaskExecutor

The central actor that manages all tasks and exposes progress updates via an async stream:

```swift
public actor TaskExecutor {
    /// Adds and starts a new task
    public func addTask(
        name: String,
        id: String? = nil,
        options: TaskOptions = .default,
        _ task: @escaping @Sendable (any TaskContext) async throws -> Void
    ) async -> String

    /// Pauses a task and all its children
    public func pause(taskID: String)

    /// Resumes a paused task and all its children
    public func resume(taskID: String)

    /// Cancels a task
    public func cancel(taskID: String)

    /// Async stream of task graph updates
    public nonisolated var progressStream: AsyncStream<TaskGraph>
}
```

Tasks can be identified by a custom string ID, or a UUID string will be generated automatically.

### TaskContext

Passed to your task function, providing methods for progress reporting and subtask creation:

```swift
public protocol TaskContext: AnyObject, Sendable {
    /// Reports progress (named step, numerical value, or both)
    func report(_ progress: TaskProgress) async throws

    /// Creates a nested subtask
    func push(_ name: String, _ step: @escaping @Sendable (any TaskContext) async throws -> Void) async throws
}
```

### TaskProgress

Represents a progress update with optional name and numerical value:

```swift
// Named step only (indeterminate)
try await context.report(.named("Processing..."))

// Numerical progress only
try await context.report(.progress(0.5))

// Both name and progress
try await context.report(.named("Step 3").progress(0.75))

// Step-based progress (automatically calculates percentage)
try await context.report(.step(3, of: 10))
```

### TaskOptions

Configures task behavior:

```swift
/// Default: cancellable, not pausable
TaskOptions.default

/// Fully interactive: both cancellable and pausable
TaskOptions.interactive

/// Immutable: cannot be cancelled or paused
TaskOptions.immutable

/// Custom options
TaskOptions(isCancellable: true, isPausable: true)
```

### TaskSnapshot

An immutable snapshot of task state for the UI:

```swift
public struct TaskSnapshot: Identifiable, Sendable, Equatable {
    public let id: String                // Custom ID or UUID string
    public let name: String
    public let progress: Float?        // nil = indeterminate
    public let stepName: String?
    public let status: TaskStatus
    public let options: TaskOptions
    public let isPaused: Bool
    public let children: [TaskSnapshot]
    public let errorDescription: String?

    // Computed properties
    public var isCompleted: Bool
    public var isFailed: Bool
    public var isRunning: Bool
}
```

## SwiftUI Integration

ProgressionUI provides ready-to-use SwiftUI views:

```swift
import ProgressionUI

struct ContentView: View {
    @StateObject private var model = MyViewModel()

    var body: some View {
        TaskProgressView(executor: model.executor)
    }
}
```

### TaskProgressView

A hierarchical tree view for displaying all tasks. This is a typealias for ``ProgressContainer`` with a default list layout:

```swift
// Default layout (name above progress bar)
TaskProgressView(executor: myExecutor)
```

### ProgressContainer

For custom layouts, use ``ProgressContainer`` directly:

```swift
ProgressContainer(executor: myExecutor) { tasks in
    // Custom rendering of tasks
    ForEach(tasks) { task in
        Text(task.name)
    }
}
```

### ProgressBar

A simple progress bar component:

```swift
// Determinate progress
ProgressBar(0.5)

// Indeterminate (animated)
ProgressBar(nil)
```

## Error Handling

Tasks can report errors that propagate to parent tasks:

```swift
try await context.push("Risky Operation") { subContext in
    do {
        try await riskyFunction()
    } catch {
        // Error propagates to parent and marks both as failed
        throw error
    }
}
```

Failed tasks display their error message and require manual dismissal.

## Advanced Usage

### Customizing Cleanup Behavior

Control how long completed tasks remain visible:

```swift
let executor = TaskExecutor()
executor.completedTaskVisibilityDuration = 2.0  // seconds
```

### Subscribing to Progress Updates

Listen for progress changes:

```swift
for await graph in executor.progressStream {
    // graph.tasks contains all current tasks
    updateUI(with: graph.tasks)
}
```

### Thread Safety

All task management operations are thread-safe:
- `TaskExecutor` is an actor, ensuring serial access
- `TaskNode` uses locks for thread-safe property access
- `TaskSnapshot` is immutable and Sendable-safe

## Requirements

- macOS 15.0+ / iOS 18.0+
- Swift 6.0+

## License

Progression is released under the MIT license. See LICENSE for details.
