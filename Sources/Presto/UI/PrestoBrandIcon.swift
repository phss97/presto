import AppKit
import CoreGraphics
import SwiftUI

/// Speech bubble card shape with a subtle, continuous-style directional tail on either bottom corner.
public struct PrestoBubbleShape: Shape {
    public enum TailSide: Sendable {
        case bottomLeft
        case bottomRight
    }

    public let tailSide: TailSide
    public let cornerRadiusRatio: CGFloat
    public let tailHeightRatio: CGFloat

    public init(
        tailSide: TailSide,
        cornerRadiusRatio: CGFloat = 0.24,
        tailHeightRatio: CGFloat = 0.11
    ) {
        self.tailSide = tailSide
        self.cornerRadiusRatio = cornerRadiusRatio
        self.tailHeightRatio = tailHeightRatio
    }

    public func path(in rect: CGRect) -> Path {
        Self.makePath(
            in: rect,
            tailSide: tailSide,
            cornerRadiusRatio: cornerRadiusRatio,
            tailHeightRatio: tailHeightRatio
        )
    }

    public static func makePath(
        in rect: CGRect,
        tailSide: TailSide,
        cornerRadiusRatio: CGFloat = 0.24,
        tailHeightRatio: CGFloat = 0.11
    ) -> Path {
        let tailH = rect.height * tailHeightRatio
        let bodyRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height - tailH
        )
        let r = min(bodyRect.width, bodyRect.height) * cornerRadiusRatio

        var path = Path()
        let minX = bodyRect.minX
        let maxX = bodyRect.maxX
        let minY = bodyRect.minY
        let maxY = bodyRect.maxY

        path.move(to: CGPoint(x: minX + r, y: minY))
        path.addLine(to: CGPoint(x: maxX - r, y: minY))
        path.addArc(
            center: CGPoint(x: maxX - r, y: minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: maxX, y: maxY - r))
        path.addArc(
            center: CGPoint(x: maxX - r, y: maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        switch tailSide {
        case .bottomRight:
            let tailTipX = maxX - r * 0.55
            let tailTipY = rect.maxY
            let tailRightBaseX = maxX - r * 0.85
            let tailLeftBaseX = maxX - r * 1.95

            path.addLine(to: CGPoint(x: tailRightBaseX, y: maxY))
            path.addQuadCurve(
                to: CGPoint(x: tailTipX, y: tailTipY),
                control: CGPoint(x: tailRightBaseX + r * 0.12, y: maxY + tailH * 0.72)
            )
            path.addQuadCurve(
                to: CGPoint(x: tailLeftBaseX, y: maxY),
                control: CGPoint(x: tailLeftBaseX + r * 0.45, y: maxY + tailH * 0.88)
            )
            path.addLine(to: CGPoint(x: minX + r, y: maxY))

        case .bottomLeft:
            let tailRightBaseX = minX + r * 1.95
            let tailLeftBaseX = minX + r * 0.85
            let tailTipX = minX + r * 0.55
            let tailTipY = rect.maxY

            path.addLine(to: CGPoint(x: tailRightBaseX, y: maxY))
            path.addQuadCurve(
                to: CGPoint(x: tailTipX, y: tailTipY),
                control: CGPoint(x: tailRightBaseX - r * 0.45, y: maxY + tailH * 0.88)
            )
            path.addQuadCurve(
                to: CGPoint(x: tailLeftBaseX, y: maxY),
                control: CGPoint(x: tailLeftBaseX - r * 0.12, y: maxY + tailH * 0.72)
            )
            path.addLine(to: CGPoint(x: minX + r, y: maxY))
        }

        path.addArc(
            center: CGPoint(x: minX + r, y: maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: minX, y: minY + r))
        path.addArc(
            center: CGPoint(x: minX + r, y: minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// Full-color macOS Liquid Glass app icon view used both to generate `AppIcon.icns` and as an in-app badge.
public struct PrestoAppIconView: View {
    public let size: CGFloat
    /// `true` for the `.icns`: square, opaque corners, no mask, letting macOS 26 draw its own squircle.
    public let fullBleed: Bool

    public init(size: CGFloat = 64, fullBleed: Bool = false) {
        self.size = size
        self.fullBleed = fullBleed
    }

    public var body: some View {
        ZStack {
            squircleBody(bodySize: size, cornerRadius: fullBleed ? 0 : size * 0.225)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func squircleBody(bodySize: CGFloat, cornerRadius: CGFloat) -> some View {
        let squircle = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            // 1. Rich sapphire-cobalt-cyan base gradient
            squircle
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.14, green: 0.62, blue: 0.99), location: 0.0),
                            .init(color: Color(red: 0.08, green: 0.35, blue: 0.88), location: 0.52),
                            .init(color: Color(red: 0.05, green: 0.14, blue: 0.45), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // 2. Luminous cyan top-left bloom + deep indigo bottom-right glow
            squircle
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.42, green: 0.88, blue: 1.0).opacity(0.45),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.22, y: 0.16),
                        startRadius: 0,
                        endRadius: bodySize * 0.65
                    )
                )

            squircle
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.36, green: 0.20, blue: 0.90).opacity(0.32),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.82, y: 0.88),
                        startRadius: 0,
                        endRadius: bodySize * 0.60
                    )
                )

            // 3. Top liquid-glass specular sheen
            squircle
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.22), location: 0.0),
                            .init(color: Color.white.opacity(0.04), location: 0.32),
                            .init(color: Color.clear, location: 0.55)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 4. Back bubble (Top-Left: Frosted translucent glass card with 'A')
            let backW = bodySize * 0.47
            let backH = bodySize * 0.44
            let backShape = PrestoBubbleShape(tailSide: .bottomLeft, cornerRadiusRatio: 0.25, tailHeightRatio: 0.10)

            ZStack {
                backShape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.34),
                                Color(red: 0.72, green: 0.90, blue: 1.0).opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        backShape
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.68),
                                        Color.white.opacity(0.18)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: max(0.75, bodySize * 0.0055)
                            )
                    }

                if bodySize >= 32 {
                    Text("A")
                        .font(.system(size: bodySize * 0.205, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.96))
                        .shadow(color: Color.black.opacity(0.16), radius: bodySize * 0.008, x: 0, y: bodySize * 0.004)
                        .offset(x: -bodySize * 0.045, y: -bodySize * 0.042)
                }
            }
            .frame(width: backW, height: backH)
            .shadow(color: Color(red: 0.02, green: 0.08, blue: 0.28).opacity(0.22), radius: bodySize * 0.022, x: 0, y: bodySize * 0.012)
            .offset(x: -bodySize * 0.115, y: -bodySize * 0.10)

            // 5. Front bubble (Bottom-Right: Crisp pearl-white glass card with '文')
            let frontW = bodySize * 0.49
            let frontH = bodySize * 0.46
            let frontShape = PrestoBubbleShape(tailSide: .bottomRight, cornerRadiusRatio: 0.25, tailHeightRatio: 0.10)

            ZStack {
                frontShape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color(red: 0.90, green: 0.96, blue: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        frontShape
                            .stroke(Color.white.opacity(0.95), lineWidth: max(0.6, bodySize * 0.004))
                    }

                Text("文")
                    .font(.system(size: bodySize * 0.225, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.07, green: 0.25, blue: 0.72),
                                Color(red: 0.11, green: 0.47, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .offset(x: 0, y: -bodySize * 0.024)
            }
            .frame(width: frontW, height: frontH)
            .shadow(
                color: Color(red: 0.02, green: 0.07, blue: 0.26).opacity(0.42),
                radius: bodySize * 0.036,
                x: -bodySize * 0.010,
                y: bodySize * 0.018
            )
            .offset(x: bodySize * 0.115, y: bodySize * 0.115)

            // 6. Outer squircle inner specular rim
            squircle
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.50), location: 0.0),
                            .init(color: Color.white.opacity(0.10), location: 0.45),
                            .init(color: Color.white.opacity(0.22), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: max(0.5, bodySize * 0.0032)
                )
        }
        // Keep the body exactly square: macOS 26 puts icons that aren't a true squircle in a gray tile.
        .frame(width: bodySize, height: bodySize)
        .clipShape(squircle)
    }
}

/// Monochrome template vector mark sharing the exact overlapping `A` + `文` bubble silhouette,
/// engineered for crisp rendering at `13–18pt` in the macOS menu bar, HUD pill, and picker header.
public struct PrestoTemplateMarkView: View {
    public let size: CGFloat

    public init(size: CGFloat = 16) {
        self.size = size
    }

    public var body: some View {
        Image(nsImage: PrestoBrandIcon.templateImage(pointSize: size))
            .interpolation(.high)
            .resizable()
            .frame(width: size, height: size)
    }
}

public enum PrestoBrandIcon {
    /// Returns a dynamic vector-backed `NSImage` with `isTemplate = true` for `MenuBarExtra` and monochrome UI slots.
    public static func menuBarTemplateImage() -> NSImage {
        templateImage(pointSize: 18)
    }

    public static func templateImage(pointSize: CGFloat = 18) -> NSImage {
        let targetSize = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: targetSize)
        for scaleFactor in [1, 2, 3] {
            let pixelDim = max(1, Int((pointSize * CGFloat(scaleFactor)).rounded()))
            if let cgImage = renderTemplateCGImage(pixelSize: pixelDim) {
                let rep = NSBitmapImageRep(cgImage: cgImage)
                rep.size = targetSize
                image.addRepresentation(rep)
            }
        }
        image.isTemplate = true
        return image
    }

    public static func renderTemplateCGImage(pixelSize: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Flip to top-left origin so coordinates match SwiftUI's coordinate system
        ctx.translateBy(x: 0, y: CGFloat(pixelSize))
        ctx.scaleBy(x: 1, y: -1)

        drawTemplateMark(in: ctx, size: CGSize(width: pixelSize, height: pixelSize))
        return ctx.makeImage()
    }

    /// CoreGraphics vector renderer using top-left flipped coordinates (`0...18` normalized grid).
    public static func drawTemplateMark(in ctx: CGContext, size: CGSize) {
        let scale = min(size.width, size.height) / 18.0
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)

        let backRect = CGRect(x: 1.0, y: 1.1, width: 10.2, height: 9.6)
        let frontRect = CGRect(x: 6.8, y: 6.9, width: 10.2, height: 9.8)

        let backBubble = PrestoBubbleShape.makePath(
            in: backRect,
            tailSide: .bottomLeft,
            cornerRadiusRatio: 0.25,
            tailHeightRatio: 0.11
        ).cgPath

        let frontBubble = PrestoBubbleShape.makePath(
            in: frontRect,
            tailSide: .bottomRight,
            cornerRadiusRatio: 0.25,
            tailHeightRatio: 0.11
        ).cgPath

        // Draw in a transparency layer so knockouts (.clear blend mode) only affect our mark
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        // 1. Back bubble: crisp stroked outline + subtle 12% frosted interior tint + geometric 'A'
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.12).cgColor)
        ctx.addPath(backBubble)
        ctx.fillPath()

        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1.35)
        ctx.setLineJoin(.round)
        ctx.addPath(backBubble)
        ctx.strokePath()

        // Geometric 'A' in upper-left of back bubble (x: 3.1...6.5, y: 3.1...7.2)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(1.25)
        let aPath = CGMutablePath()
        aPath.move(to: CGPoint(x: 3.25, y: 7.05))
        aPath.addLine(to: CGPoint(x: 4.80, y: 3.15))
        aPath.addLine(to: CGPoint(x: 6.35, y: 7.05))
        aPath.move(to: CGPoint(x: 3.72, y: 5.85))
        aPath.addLine(to: CGPoint(x: 5.88, y: 5.85))
        ctx.addPath(aPath)
        ctx.strokePath()
        ctx.restoreGState()

        // 2. Knockout halo around front bubble so the overlap reads cleanly at 16-18pt
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.addPath(frontBubble)
        ctx.fillPath()
        ctx.setLineWidth(2.5)
        ctx.setLineJoin(.round)
        ctx.addPath(frontBubble)
        ctx.strokePath()
        ctx.restoreGState()

        // 3. Solid front bubble
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(frontBubble)
        ctx.fillPath()
        ctx.restoreGState()

        // 4. Knock out crisp geometric '文' inside front bubble (center ~ (11.9, 11.3))
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(1.28)

        let wenPath = CGMutablePath()
        // Top short dot/stroke
        wenPath.move(to: CGPoint(x: 11.90, y: 8.55))
        wenPath.addLine(to: CGPoint(x: 11.90, y: 9.65))
        // Horizontal top bar
        wenPath.move(to: CGPoint(x: 9.25, y: 9.75))
        wenPath.addLine(to: CGPoint(x: 14.55, y: 9.75))
        // Right-to-left sweeping stroke (丿)
        wenPath.move(to: CGPoint(x: 13.35, y: 9.85))
        wenPath.addQuadCurve(
            to: CGPoint(x: 9.35, y: 13.85),
            control: CGPoint(x: 12.45, y: 12.45)
        )
        // Left-to-right sweeping stroke (捺)
        wenPath.move(to: CGPoint(x: 10.35, y: 10.55))
        wenPath.addQuadCurve(
            to: CGPoint(x: 14.45, y: 13.85),
            control: CGPoint(x: 11.65, y: 12.55)
        )

        ctx.addPath(wenPath)
        ctx.strokePath()
        ctx.restoreGState()

        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
