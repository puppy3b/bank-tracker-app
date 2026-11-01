#!/usr/bin/env swift
//
// Renders the sidebar logo (the AppMark image set) from the app icon, in light and dark.
//
// The app icon is an Icon Composer document, BankTracker/AppIcon.icon. Edit it in
// Icon Composer (Xcode ▸ Open Developer Tool ▸ Icon Composer). Xcode builds the Liquid Glass
// icon from it, along with flat icons for macOS 15 and iOS 18. Run this script afterwards
// so the sidebar logo matches.
//
// Usage: swift scripts/make-icon.swift

import Foundation

let icon = URL(fileURLWithPath: "BankTracker/AppIcon.icon")
let mark = URL(fileURLWithPath: "BankTracker/Assets.xcassets/AppMark.imageset")

struct ScriptError: Error, CustomStringConvertible {
    let description: String
}

@discardableResult
func run(_ executable: URL, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw ScriptError(description: "\(executable.lastPathComponent) failed with status \(process.terminationStatus)")
    }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

// ictool ships inside Icon Composer, which comes with Xcode 26 and later.
let developer = try run(URL(fileURLWithPath: "/usr/bin/xcode-select"), ["-p"])
let ictool = URL(fileURLWithPath: developer)
    .deletingLastPathComponent()
    .appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool")
guard FileManager.default.isExecutableFile(atPath: ictool.path) else {
    throw ScriptError(description: "Icon Composer's ictool wasn't found at \(ictool.path). Install Xcode 26 or later.")
}
guard FileManager.default.fileExists(atPath: icon.path) else {
    throw ScriptError(description: "Run this from the repository root; \(icon.path) wasn't found.")
}

try FileManager.default.createDirectory(at: mark, withIntermediateDirectories: true)

// 128 points at 2x: the sidebar shows it at 24 points, so it stays sharp on any display.
let renditions = [("Default", "app-mark.png"), ("Dark", "app-mark-dark.png")]
for (rendition, file) in renditions {
    try run(ictool, [
        icon.path, "--export-image",
        "--output-file", mark.appendingPathComponent(file).path,
        "--platform", "macOS", "--rendition", rendition,
        "--width", "128", "--height", "128", "--scale", "2",
    ])
}

let contents: [String: Any] = [
    "images": [
        ["filename": "app-mark.png", "idiom": "universal"],
        [
            "appearances": [["appearance": "luminosity", "value": "dark"]],
            "filename": "app-mark-dark.png",
            "idiom": "universal",
        ],
    ],
    "info": ["author": "xcode", "version": 1],
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: mark.appendingPathComponent("Contents.json"))
print("Wrote the light and dark sidebar logo to \(mark.path)")
