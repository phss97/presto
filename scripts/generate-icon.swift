import AppKit
import Foundation
import ImageIO
import SwiftUI

@MainActor
enum IconGeneratorMain {
    static func renderPNG(view: some View, pointSize: Int, scale: Int, to url: URL) throws {
        let pixelSize = pointSize * scale
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        renderer.proposedSize = ProposedViewSize(width: CGFloat(pixelSize), height: CGFloat(pixelSize))

        guard let cgImage = renderer.cgImage else {
            throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to rasterize icon at \(pixelSize)px"])
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        bitmap.size = NSSize(width: pointSize, height: pointSize)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "IconGen", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }
        try pngData.write(to: url)
    }

    static func generateICNS(outputICNS: URL, previewDir: URL?) throws {
        let fm = FileManager.default
        let tempIconset = fm.temporaryDirectory.appendingPathComponent("Presto-\(UUID().uuidString).iconset", isDirectory: true)
        try fm.createDirectory(at: tempIconset, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: tempIconset)
        }

        let specs: [(name: String, points: Int, scale: Int)] = [
            ("icon_16x16.png", 16, 1),
            ("icon_16x16@2x.png", 16, 2),
            ("icon_32x32.png", 32, 1),
            ("icon_32x32@2x.png", 32, 2),
            ("icon_128x128.png", 128, 1),
            ("icon_128x128@2x.png", 128, 2),
            ("icon_256x256.png", 256, 1),
            ("icon_256x256@2x.png", 256, 2),
            ("icon_512x512.png", 512, 1),
            ("icon_512x512@2x.png", 512, 2)
        ]

        for spec in specs {
            let pixels = spec.points * spec.scale
            let iconView = PrestoAppIconView(size: CGFloat(pixels), fullBleed: true)
            try renderPNG(
                view: iconView,
                pointSize: spec.points,
                scale: spec.scale,
                to: tempIconset.appendingPathComponent(spec.name)
            )
        }

        try fm.createDirectory(at: outputICNS.deletingLastPathComponent(), withIntermediateDirectories: true)

        // iconutil maps each iconset filename to its own slot; CGImageDestination inferred slots
        // from pixel size and wrote duplicate entries for 16pt@2x and 32pt@1x.
        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", tempIconset.path, "-o", outputICNS.path]
        try iconutil.run()
        iconutil.waitUntilExit()
        guard iconutil.terminationStatus == 0 else {
            throw NSError(domain: "IconGen", code: 5, userInfo: [NSLocalizedDescriptionKey: "iconutil failed while building \(outputICNS.path)"])
        }

        if let previewDir {
            try fm.createDirectory(at: previewDir, withIntermediateDirectories: true)
            let showcase = IconSystemShowcaseView()
            let renderer = ImageRenderer(content: showcase)
            renderer.scale = 2.0
            if let cgImage = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cgImage)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try data.write(to: previewDir.appendingPathComponent("presto-icon-showcase.png"))
                }
            }
        }
    }
}

private struct IconSystemShowcaseView: View {
    var body: some View {
        VStack(spacing: 28) {
            HStack(spacing: 36) {
                VStack(spacing: 10) {
                    PrestoAppIconView(size: 220)
                    Text("App Icon (macOS Squircle)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    // Simulated Dark macOS Menu Bar
                    HStack(spacing: 16) {
                        Image(systemName: "wifi")
                        PrestoMenuBarSimulatedTint(isDarkBar: true)
                        Image(systemName: "battery.100")
                        Text("Wed Nov 11  4:58 PM")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 0.11, green: 0.13, blue: 0.18))
                    )

                    // Simulated Light macOS Menu Bar
                    HStack(spacing: 16) {
                        Image(systemName: "wifi")
                        PrestoMenuBarSimulatedTint(isDarkBar: false)
                        Image(systemName: "battery.100")
                        Text("Wed Nov 11  4:58 PM")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.black.opacity(0.88))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 0.91, green: 0.93, blue: 0.96))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                            }
                    )

                    // Zoomed Menu Bar Vector Inspection + Small App Sizes
                    HStack(spacing: 20) {
                        VStack(spacing: 4) {
                            PrestoMenuBarSimulatedTint(isDarkBar: false, pointSize: 44)
                            Text("Menu Bar Mark")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        VStack(spacing: 4) {
                            PrestoAppIconView(size: 48)
                            Text("Settings 48pt")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        VStack(spacing: 4) {
                            PrestoAppIconView(size: 22)
                            Text("Popover 22pt")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(32)
        .background(Color(red: 0.97, green: 0.97, blue: 0.98))
    }
}

private struct PrestoMenuBarSimulatedTint: View {
    let isDarkBar: Bool
    var pointSize: CGFloat = 18

    var body: some View {
        Image(nsImage: PrestoBrandIcon.templateImage(pointSize: pointSize))
            .renderingMode(.template)
            .resizable()
            .frame(width: pointSize, height: pointSize)
            .foregroundStyle(isDarkBar ? Color.white : Color.black.opacity(0.88))
    }
}

@main
struct GenerateIconCLI {
    @MainActor
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            fputs("Usage: generate-icon <output.icns> [preview-dir]\n", stderr)
            exit(1)
        }
        let icnsURL = URL(fileURLWithPath: args[1])
        let previewURL = args.count >= 3 ? URL(fileURLWithPath: args[2]) : nil
        try IconGeneratorMain.generateICNS(outputICNS: icnsURL, previewDir: previewURL)
    }
}
