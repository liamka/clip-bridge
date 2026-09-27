// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipBridge",
    platforms: [.macOS(.v13)],
    targets: [
        // Слой данных: история, правила записи, сборка контекста. Только Foundation.
        .target(name: "ClipBridgeCore"),
        // Приложение: строка меню, хоткей, окно. К данным — только через ClipBridgeCore.
        .executableTarget(name: "ClipBridge", dependencies: ["ClipBridgeCore"]),
        // Автопроверки ядра (XCTest в Command Line Tools недоступен).
        .executableTarget(name: "CoreChecks", dependencies: ["ClipBridgeCore"]),
    ]
)
