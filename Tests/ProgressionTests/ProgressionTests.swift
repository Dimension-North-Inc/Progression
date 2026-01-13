//
//  ProgressionTests.swift
//  Progression
//
//  Created by Mark Onyschuk on 1/13/26.
//  Copyright © 2026 by Dimension North Inc, All Rights Reserved.
//

import XCTest
@testable import Progression

/// A thread-safe container for Sendable compliance.
final class Locked<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func withValue<R>(_ block: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return block(&_value)
    }
}

final class ProgressionTests: XCTestCase {

    // MARK: - TaskNode Tests

    func testTaskNodeCreation() {
        let node = TaskNode(name: "Test Task")
        XCTAssertEqual(node.name, "Test Task")
        XCTAssertEqual(node.progress, 0.0)
        XCTAssertEqual(statusToString(node.status), "pending")
        XCTAssertFalse(node.hasChildren)
    }

    func testTaskNodeAddChild() {
        let parent = TaskNode(name: "Parent")
        let child = TaskNode(name: "Child")

        parent.addChild(child)

        XCTAssertTrue(parent.hasChildren)
        XCTAssertEqual(parent.children.count, 1)
        XCTAssertEqual(parent.children.first?.name, "Child")
    }

    func testTaskNodeProgressUpdate() {
        let node = TaskNode(name: "Test Task")
        node.progress = 0.5
        XCTAssertEqual(node.progress, 0.5)

        node.progress = 1.5
        XCTAssertEqual(node.progress, 1.0) // Capped at 1.0

        node.progress = -0.5
        XCTAssertEqual(node.progress, 0.0) // Capped at 0.0
    }

    func testTaskNodeStepNameUpdate() {
        let node = TaskNode(name: "Test Task")
        node.stepName = "Step 1"
        XCTAssertEqual(node.stepName, "Step 1")

        node.stepName = "Step 2"
        XCTAssertEqual(node.stepName, "Step 2")
    }

    func testTaskNodeExpandedToggle() {
        let node = TaskNode(name: "Test Task")
        XCTAssertTrue(node.isExpanded)

        node.toggleExpanded()
        XCTAssertFalse(node.isExpanded)
    }

    func testTaskNodeRecalculateProgress() {
        let parent = TaskNode(name: "Parent")
        let child1 = TaskNode(name: "Child 1")
        let child2 = TaskNode(name: "Child 2")

        child1.progress = 0.5
        child2.progress = 1.0

        parent.addChild(child1)
        parent.addChild(child2)
        parent.recalculateProgress()

        XCTAssertEqual(parent.progress ?? 0.0, 0.75 as Float)
    }

    // MARK: - TaskProgress Tests

    func testTaskProgressProgressValue() {
        let progress = TaskProgress.progress(0.75)
        XCTAssertEqual(progress.name, "Processing")
        XCTAssertEqual(progress.completeness, 0.75)
        XCTAssertFalse(progress.isIndeterminate)
        XCTAssertFalse(progress.isComplete)
    }

    func testTaskProgressNamed() {
        let progress = TaskProgress.named("Step Name")
        XCTAssertEqual(progress.name, "Step Name")
        XCTAssertNil(progress.completeness)
        XCTAssertTrue(progress.isIndeterminate)
    }

    func testTaskProgressStep() {
        let progress = TaskProgress.step(3, of: 10)
        XCTAssertEqual(progress.name, "Processing")
        XCTAssertEqual(progress.completeness, 0.3)
    }

    func testTaskProgressCompleted() {
        let progress = TaskProgress.completed
        XCTAssertEqual(progress.name, "Complete")
        XCTAssertEqual(progress.completeness, 1.0)
        XCTAssertTrue(progress.isComplete)
    }

    func testTaskProgressModifier() {
        let base = TaskProgress.named("Initial")
        let modified = base.progress(0.5)
        XCTAssertEqual(modified.name, "Initial")
        XCTAssertEqual(modified.completeness, 0.5)

        let namedModified = modified.named("Updated")
        XCTAssertEqual(namedModified.name, "Updated")
        XCTAssertEqual(namedModified.completeness, 0.5)
    }

    func testTaskProgressClampedCompleteness() {
        let tooHigh = TaskProgress.progress(1.5)
        XCTAssertEqual(tooHigh.clampedCompleteness, 1.0)

        let tooLow = TaskProgress.progress(-0.5)
        XCTAssertEqual(tooLow.clampedCompleteness, 0.0)

        let normal = TaskProgress.progress(0.5)
        XCTAssertEqual(normal.clampedCompleteness, 0.5)
    }

    // MARK: - TaskExecutor Tests

    func testTaskExecutorCreation() async {
        let executor = TaskExecutor()
        let tasks = await executor.allTasks
        XCTAssertEqual(tasks.count, 0)
    }

    func testAddTask() async throws {
        let executor = TaskExecutor()

        _ = await executor.addTask(
            name: "Test Task",
            options: .default
        ) { context in
            try await context.report(.progress(0.25))
            try await context.report(.progress(0.5))
            try await context.report(.progress(1.0))
        }

        // Give the task time to complete
        try await Task.sleep(for: .milliseconds(100))

        let tasks = await executor.allTasks
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.name, "Test Task")
        XCTAssertEqual(tasks.first?.progress, 1.0)
        XCTAssertEqual(statusToString(tasks.first?.status), "completed")
    }

    func testAddTaskWithSubtask() async throws {
        let executor = TaskExecutor()

        await executor.addTask(
            name: "Main Task",
            options: .default
        ) { context in
            try await context.report(.named("Starting"))

            try await context.push("Subtask") { subContext in
                try await subContext.report(.progress(0.5))
            }

            try await context.report(.progress(1.0))
        }

        // Give the task time to complete
        try await Task.sleep(for: .milliseconds(100))

        let tasks = await executor.allTasks
        XCTAssertEqual(tasks.count, 1)
        let mainTask = tasks.first
        XCTAssertEqual(mainTask?.children.count, 1)
        XCTAssertEqual(mainTask?.children.first?.name, "Subtask")
    }

    func testNestedPush() async throws {
        let executor = TaskExecutor()

        await executor.addTask(
            name: "Main Task",
            options: .default
        ) { context in
            try await context.report(.progress(0.5))

            try await context.push("Nested") { nestedContext in
                try await nestedContext.report(.progress(0.25))

                try await nestedContext.push("Deep") { deepContext in
                    try await deepContext.report(.progress(0.1))
                }
            }

            try await context.report(.progress(1.0))
        }

        // Give the task time to complete
        try await Task.sleep(for: .milliseconds(100))

        let tasks = await executor.allTasks
        XCTAssertEqual(tasks.count, 1)
        let nestedChildren = tasks.first?.children
        XCTAssertEqual(nestedChildren?.count, 1)
        XCTAssertEqual(nestedChildren?.first?.children.count, 1)
    }

    func testCancelAll() async {
        let executor = TaskExecutor()

        // Add a task
        await executor.addTask(
            name: "Test Task",
            options: .default
        ) { _ in
            try await Task.sleep(for: .seconds(10))
        }

        // Cancel it
        await executor.cancelAll()

        let tasks = await executor.allTasks
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(statusToString(tasks.first?.status), "cancelled")
    }

    func testRemoveCompletedTasks() async throws {
        let executor = TaskExecutor()

        // Add a task that completes
        await executor.addTask(
            name: "Completed Task",
            options: .default
        ) { context in
            try await context.report(.progress(1.0))
        }

        // Wait for completion
        try await Task.sleep(for: .milliseconds(100))

        // Add another task
        await executor.addTask(
            name: "Another Task",
            options: .default
        ) { context in
            try await context.report(.progress(0.5))
        }

        // Remove completed tasks
        await executor.removeCompletedTasks()

        let tasks = await executor.allTasks
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.name, "Another Task")
    }

    func testProgressStream() async throws {
        let executor = TaskExecutor()
        let updates = Locked<[TaskGraph]>([])

        let task = Task { @Sendable in
            for await graph in executor.progressStream {
                updates.withValue { $0.append(graph) }

                // Stop after we have enough updates
                if let lastTask = graph.tasks.last,
                   lastTask.isCompleted {
                    break
                }
            }
        }

        // Start a task
        await executor.addTask(
            name: "Test Task",
            options: .default
        ) { context in
            try await context.report(.progress(0.25))
            try await context.report(.progress(0.5))
            try await context.report(.progress(1.0))
        }

        await task.value

        let allUpdates = updates.value
        XCTAssertGreaterThan(allUpdates.count, 0)
        if let lastUpdate = allUpdates.last {
            XCTAssertEqual(lastUpdate.tasks.count, 1)
            XCTAssertEqual(lastUpdate.tasks.first?.progress, 1.0)
        }
    }

    func testComplexMultiStepTask() async throws {
        let executor = TaskExecutor()

        await executor.addTask(
            name: "Import Data",
            options: .default
        ) { context in
            try await context.report(.named("Contemplating"))
            try await Task.sleep(nanoseconds: 10_000_000)

            try await context.report(.progress(0.1))
            try await context.report(.named("Downloading data..."))
            try await Task.sleep(nanoseconds: 10_000_000)
            try await context.report(.progress(0.5))

            try await context.push("Parse") { parseContext in
                try await parseContext.report(.named("Parsing records..."))
                try await Task.sleep(nanoseconds: 5_000_000)
                try await parseContext.report(.progress(0.3))
                try await parseContext.report(.progress(1.0))
            }

            try await context.report(.progress(0.8))
            try await context.report(.progress(1.0))
        }

        // Give the task time to complete
        try await Task.sleep(for: .milliseconds(200))

        let tasks = await executor.allTasks
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.children.count, 1)
        XCTAssertTrue(isStatusCompleted(tasks.first?.children.first?.status))
        XCTAssertEqual(tasks.first?.progress, 1.0)
    }

    // MARK: - TaskOptions Tests

    func testTaskOptionsDefault() {
        let options = TaskOptions.default
        XCTAssertTrue(options.isCancellable)
        XCTAssertFalse(options.isPausable)
    }

    func testTaskOptionsImmutable() {
        let options = TaskOptions.immutable
        XCTAssertFalse(options.isCancellable)
        XCTAssertFalse(options.isPausable)
    }

    func testTaskOptionsInteractive() {
        let options = TaskOptions.interactive
        XCTAssertTrue(options.isCancellable)
        XCTAssertTrue(options.isPausable)
    }

    func testTaskOptionsCustom() {
        let options = TaskOptions(isCancellable: false, isPausable: true)
        XCTAssertFalse(options.isCancellable)
        XCTAssertTrue(options.isPausable)
    }

    func testTaskOptionsEquality() {
        let options1 = TaskOptions(isCancellable: true, isPausable: false)
        let options2 = TaskOptions(isCancellable: true, isPausable: false)
        let options3 = TaskOptions(isCancellable: false, isPausable: false)
        XCTAssertEqual(options1, options2)
        XCTAssertNotEqual(options1, options3)
    }

    // MARK: - TaskNode Pause Tests

    func testTaskNodePauseResume() {
        let node = TaskNode(name: "Test")

        // Initial state
        XCTAssertFalse(node.isPaused)

        // Pause
        node.pause()
        XCTAssertTrue(node.isPaused)

        // Pause again
        node.pause()
        XCTAssertTrue(node.isPaused)

        // Resume
        node.resume()
        XCTAssertFalse(node.isPaused)

        // Resume again
        node.resume()
        XCTAssertFalse(node.isPaused)
    }

    // MARK: - Async Pause/Resume Tests

    func testPauseResumeDuringTask() async throws {
        let executor = TaskExecutor()

        let _ = Locked(false) // isPaused tracking
        let hasResumed = Locked(false)

        await executor.addTask(
            name: "Paused Task",
            options: .interactive
        ) { context in
            try await context.report(.named("Starting"))

            // Report that will block if paused
            try await context.report(.progress(0.0))

            // Mark that we got past the pause
            hasResumed.withValue { $0 = true }
        }

        // Get the task ID
        let tasks = await executor.allTasks
        guard let taskID = tasks.first?.id else {
            XCTFail("Task should exist")
            return
        }

        // Pause the task
        await executor.pause(taskID: taskID)

        // Give it time to process
        try await Task.sleep(for: .milliseconds(50))

        // Resume the task
        await executor.resume(taskID: taskID)

        // Wait for completion
        try await Task.sleep(for: .milliseconds(100))

        let completedTasks = await executor.allTasks
        XCTAssertEqual(completedTasks.first?.status, .completed)
    }

    func testMultipleConcurrentTasksIsolation() async throws {
        let executor = TaskExecutor()
        let task1Progress = Locked(0.0)
        let task2Progress = Locked(0.0)

        // Add first task
        await executor.addTask(
            name: "Task 1",
            options: .interactive
        ) { context in
            try await context.report(.progress(0.0))
            try await context.report(.progress(0.5))
            task1Progress.withValue { $0 = 0.5 }
            try await context.report(.progress(1.0))
            task1Progress.withValue { $0 = 1.0 }
        }

        // Add second task immediately after
        await executor.addTask(
            name: "Task 2",
            options: .interactive
        ) { context in
            try await context.report(.progress(0.0))
            try await context.report(.progress(1.0))
            task2Progress.withValue { $0 = 1.0 }
        }

        // Wait for both to complete
        try await Task.sleep(for: .milliseconds(200))

        let tasks = await executor.allTasks
        XCTAssertEqual(tasks.count, 2)

        // Verify both tasks completed independently
        let task1 = tasks.first { $0.name == "Task 1" }
        let task2 = tasks.first { $0.name == "Task 2" }

        XCTAssertEqual(task1?.status, .completed)
        XCTAssertEqual(task2?.status, .completed)
        XCTAssertEqual(task1Progress.value, 1.0)
        XCTAssertEqual(task2Progress.value, 1.0)
    }

    func testCancelSpecificTask() async throws {
        let executor = TaskExecutor()

        await executor.addTask(
            name: "Task to Cancel",
            options: .default
        ) { _ in
            try await Task.sleep(for: .seconds(10))
        }

        await executor.addTask(
            name: "Task to Keep",
            options: .default
        ) { context in
            try await context.report(.progress(0.5))
        }

        let tasks = await executor.allTasks
        let taskToCancelID = tasks.first { $0.name == "Task to Cancel" }?.id

        guard let id = taskToCancelID else {
            XCTFail("Task should exist")
            return
        }

        await executor.cancel(taskID: id)

        let updatedTasks = await executor.allTasks
        let cancelled = updatedTasks.first { $0.name == "Task to Cancel" }
        let kept = updatedTasks.first { $0.name == "Task to Keep" }

        XCTAssertEqual(cancelled?.status, .cancelled)
        XCTAssertEqual(kept?.status, .completed)
    }

    func testErrorPropagation() async throws {
        let executor = TaskExecutor()

        struct TestError: Error, Equatable {
            let message: String
        }

        await executor.addTask(
            name: "Parent Task",
            options: .default
        ) { context in
            try await context.report(.named("Starting"))

            do {
                try await context.push("Child Task") { _ in
                    throw TestError(message: "Child failed")
                }
            } catch {
                // Error should propagate, parent will be marked as failed
            }
        }

        // Wait for error to propagate
        try await Task.sleep(for: .milliseconds(100))

        let tasks = await executor.allTasks
        XCTAssertEqual(tasks.count, 1)

        // Parent should be marked as failed
        if case .failed(let error) = tasks.first?.status {
            XCTAssertEqual(String(describing: error), "Child failed")
        } else {
            XCTFail("Parent should be failed")
        }
    }

    // MARK: - Helpers

    private func statusToString(_ status: TaskStatus?) -> String {
        guard let status = status else { return "nil" }
        switch status {
        case .pending: return "pending"
        case .running: return "running"
        case .completed: return "completed"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        }
    }

    private func isStatusCompleted(_ status: TaskStatus?) -> Bool {
        guard case .completed = status else { return false }
        return true
    }
}
