# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2025-01-13

### Added
- Initial release with core task management features
- Hierarchical task support with subtasks
- Progress reporting with named steps and numerical values
- Pause/resume functionality for tasks and children
- Cancellation support with automatic cleanup
- Error propagation from subtasks to parents
- SwiftUI views for task progress display
- Indeterminate progress animation
- Task visibility duration control
- Customizable row layouts for SwiftUI

### Core Modules
- `Progression` - Core task execution and progress tracking
- `ProgressionUI` - SwiftUI components for displaying task progress
- `Demo` - Example application demonstrating usage
