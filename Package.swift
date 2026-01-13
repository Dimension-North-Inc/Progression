//
//  Package.swift
//  Progression
//
//  Created by Mark Onyschuk on 1/13/26.
//  Copyright © 2026 by Dimension North Inc, All Rights Reserved.
//

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Progression",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "Progression",
            targets: ["Progression"]
        ),
        .library(
            name: "ProgressionUI",
            targets: ["ProgressionUI"]
        ),
        .executable(
            name: "Demo",
            targets: ["Demo"]
        )
    ],
    targets: [
        .target(
            name: "Progression",
            dependencies: []
        ),
        .target(
            name: "ProgressionUI",
            dependencies: ["Progression"]
        ),
        .executableTarget(
            name: "Demo",
            dependencies: ["Progression", "ProgressionUI"]
        ),
        .testTarget(
            name: "ProgressionTests",
            dependencies: ["Progression"]
        )
    ],
    swiftLanguageModes: [.v6]
)
