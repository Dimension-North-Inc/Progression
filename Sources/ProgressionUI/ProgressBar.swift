//
//  ProgressBar.swift
//  Progression
//
//  Created by Mark Onyschuk on 1/13/26.
//  Copyright © 2026 by Dimension North Inc, All Rights Reserved.
//

import SwiftUI

/// A progress bar for displaying task completion.
///
/// This view wraps SwiftUI's native `ProgressView` with a consistent
/// linear style and support for both determinate and indeterminate modes.
///
/// ## Example
///
/// ```swift
/// // Determinate progress
/// ProgressBar(0.5)
///
/// // Indeterminate (animated)
/// ProgressBar(nil)
/// ```
///
/// ## See Also
///
/// - ``TaskProgressView``
public struct ProgressBar: View {
    /// The progress value, from 0.0 to 1.0, or nil for indeterminate.
    public let progress: Double?

    /// Creates a progress bar.
    ///
    /// - Parameter progress: A value between 0.0 and 1.0 for determinate progress,
    ///   or `nil` for an indeterminate (animated) progress bar.
    public init(_ progress: Float?) {
        self.progress = progress.map(Double.init)
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
        ForEach([0.0, 0.25, 0.5, 0.75, 1.0] as [Double], id: \.self) { progress in
            ProgressBar(Float(progress))
        }

        ProgressBar(nil) // Indeterminate
    }
    .frame(maxWidth: 200)
    .padding()
}
