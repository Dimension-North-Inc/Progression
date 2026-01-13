import SwiftUI

/// A progress bar view for displaying task completion.
///
/// This view wraps SwiftUI's native `ProgressView` with a consistent
/// linear style and support for both determinate and indeterminate modes.
///
/// ## Example
///
/// ```swift
/// // Determinate progress
/// ProgressBarView(progress: 0.5)
///
/// // Indeterminate (animated)
/// ProgressBarView(progress: nil)
/// ```
///
/// ## See Also
///
/// - ``TaskProgressView``
public struct ProgressBarView: View {
    /// The progress value, from 0.0 to 1.0, or nil for indeterminate.
    public let progress: Double?

    /// Creates a progress bar.
    ///
    /// - Parameter progress: A value between 0.0 and 1.0 for determinate progress,
    ///   or `nil` for an indeterminate (animated) progress bar.
    public init(progress: Double?) {
        self.progress = progress
    }

    public var body: some View {
        if let progress, progress >= 0 {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(.gray)
        } else {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(.gray)
        }
    }
}

#Preview {
    VStack {
        ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { progress in
            ProgressBarView(progress: progress)
        }

        ProgressBarView(progress: nil)  // Indeterminate
    }
    .frame(maxWidth: 200)
    .padding()
}
