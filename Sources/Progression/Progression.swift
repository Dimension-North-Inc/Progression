/// Progression
///
/// A Swift package for managing hierarchical task execution with progress tracking,
/// cancellation, and pause/resume support.
///
/// ## Overview
///
/// Progression provides a type-safe, actor-based system for:
/// - **Hierarchical Tasks**: Tasks can have nested subtasks with automatic progress aggregation
/// - **Progress Reporting**: Report named steps and numerical progress (0.0 to 1.0)
/// - **Cancellation**: Safely cancel running tasks at any level
/// - **Pause/Resume**: Pause tasks and all their children simultaneously
/// - **Error Propagation**: Errors in subtasks propagate to parent tasks
///
/// ## Quick Start
///
/// ```swift
/// import Progression
///
/// let executor = TaskExecutor()
///
/// await executor.addTask(name: "Data Import", options: .interactive) { context in
///     try await context.report(.named("Initializing..."))
///     try await Task.sleep(for: .seconds(1))
///
///     try await context.report(.progress(0.2))
///
///     try await context.push("Downloading files") { downloadContext in
///         for i in 1...10 {
///             try await Task.sleep(for: .milliseconds(100))
///             try await downloadContext.report(.progress(Double(i) / 10.0))
///         }
///     }
///
///     try await context.report(.progress(1.0))
/// }
/// ```
///
/// ## Topics
///
/// ### Core Concepts
///
/// - ``TaskExecutor`` - Central actor managing all tasks
/// - ``TaskContext`` - Context passed to task functions for progress reporting
/// - ``TaskProgress`` - Progress update representation
/// - ``TaskOptions`` - Task configuration options
///
/// ### Data Types
///
/// - ``TaskNode`` - Internal task node representation
/// - ``TaskSnapshot`` - Immutable snapshot for UI binding
/// - ``TaskStatus`` - Possible task states
/// - ``TaskGraph`` - Complete task graph state
///
/// ### Error Handling
///
/// - ``ProgressionError`` - Errors that can occur during task execution
///
/// ## See Also
///
/// - ``ProgressionUI`` - SwiftUI views for displaying task progress
public enum Progression {}
