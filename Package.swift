// swift-tools-version: 5.9
//
//  Package.swift
//  KitoChat
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import PackageDescription

let package = Package(
    name: "KitoChat",
    platforms: [.iOS(.v17)],
    products: [.library(name: "KitoChat", targets: ["KitoChat"])],
    dependencies: [
        .package(url: "https://github.com/WykSofts-Inc/KitoCore.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "KitoChat", dependencies: [.product(name: "KitoCore", package: "KitoCore")]),
        .testTarget(name: "KitoChatTests", dependencies: ["KitoChat"]),
    ]
)
