import SwiftUI

/// Draws a `GameWorld` into a SwiftUI `Canvas`. All graphics are vector
/// drawing: no image assets.
enum GameRenderer {
    static func draw(_ world: GameWorld, in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return }
        let scale = size.height / GameWorld.height
        let width = world.width
        let palette = SkyPalette.at(world.dayProgress)

        var ctx = context
        ctx.scaleBy(x: scale, y: scale)

        // Screen shake for crashes.
        var scene = ctx
        if world.shake > 0 {
            let amount = world.shake * world.shake * 18
            scene.translateBy(x: sin(world.clock * 97) * amount, y: cos(world.clock * 83) * amount)
        }

        drawSky(&scene, world: world, palette: palette, width: width)
        drawCelestials(&scene, world: world, palette: palette, width: width)
        drawRidge(&scene, width: width, offset: world.distance * 0.05, baseY: 560, amplitude: 170,
                  frequency: 0.0055, seed: 1.3, peaky: true,
                  top: palette.farMountain, bottom: palette.farMountain.mix(palette.horizon, 0.65))
        drawClouds(&scene, world: world, palette: palette)
        drawRidge(&scene, width: width, offset: world.distance * 0.11, baseY: 650, amplitude: 120,
                  frequency: 0.009, seed: 4.2, peaky: true,
                  top: palette.nearMountain, bottom: palette.nearMountain.mix(palette.horizon, 0.45))
        drawMist(&scene, palette: palette, width: width)
        drawRidge(&scene, width: width, offset: world.distance * 0.25, baseY: 750, amplitude: 42,
                  frequency: 0.012, seed: 2.7, peaky: false,
                  top: palette.hill.lighter(0.12), bottom: palette.hill.darker(0.1))
        drawBushes(&scene, world: world, palette: palette, width: width)

        // The foreground gets the tint of the time of day. `sourceAtop` only
        // colors the pixels that the foreground covers.
        scene.drawLayer { layer in
            for pipe in world.pipes {
                drawPipe(&layer, pipe: pipe, world: world)
            }
            drawGround(&layer, world: world, width: width)
            drawBirdShadow(&layer, world: world)
            drawBird(&layer, world: world)
            if palette.tintAmount > 0.001 {
                layer.blendMode = .sourceAtop
                layer.fill(Path(CGRect(x: -50, y: -50, width: width + 100, height: GameWorld.height + 100)),
                           with: .color(palette.tint.withOpacity(palette.tintAmount)))
            }
        }
        drawParticles(&scene, world: world)

        drawHUD(&ctx, world: world, width: width)
        drawVignette(&ctx, width: width)

        if world.flash > 0 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: width, height: GameWorld.height)),
                     with: .color(.white.opacity(world.flash * 0.75)))
        }
    }

    // MARK: - Background

    private static func drawSky(_ ctx: inout GraphicsContext, world: GameWorld, palette: SkyPalette, width: Double) {
        let rect = CGRect(x: -40, y: -40, width: width + 80, height: GameWorld.height + 80)
        ctx.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [palette.top.color, palette.top.mix(palette.horizon, 0.5).color, palette.horizon.color]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 0, y: GameWorld.groundY - 120)
        ))

        guard palette.stars > 0.01 else { return }
        for i in 0..<80 {
            let x = hash(i) * width
            let y = hash(i + 500) * 560
            let twinkle = 0.55 + 0.45 * sin(world.clock * (1.5 + hash(i + 900) * 3) + Double(i))
            let radius = 1.2 + hash(i + 1300) * 2.4
            ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(.white.opacity(palette.stars * twinkle)))
        }
    }

    private static func drawCelestials(_ ctx: inout GraphicsContext, world: GameWorld, palette: SkyPalette, width: Double) {
        let t = world.dayProgress

        // Sun: rises in the morning, sets at dusk.
        if t < 0.6 {
            let p = t / 0.6
            let altitude = sin(p * .pi)
            let center = CGPoint(x: width * (0.08 + 0.84 * p), y: 620 - altitude * 450)
            let glowColor = RGB(0xFFB347).mix(RGB(0xFFF4C0), altitude)
            radialGlow(&ctx, center: center, radius: 190, color: glowColor, opacity: 0.55)
            let disc = Path(ellipseIn: CGRect(x: center.x - 48, y: center.y - 48, width: 96, height: 96))
            ctx.fill(disc, with: .radialGradient(
                Gradient(colors: [RGB(0xFFFBE0).color, RGB(0xFFD54A).mix(RGB(0xFF8A3D), 1 - altitude).color]),
                center: center, startRadius: 0, endRadius: 50
            ))
        }

        // Moon: crosses the sky at night.
        if t > 0.55 {
            let p = (t - 0.55) / 0.45
            let altitude = sin(p * .pi)
            let center = CGPoint(x: width * (0.1 + 0.8 * p), y: 600 - altitude * 430)
            radialGlow(&ctx, center: center, radius: 130, color: RGB(0xCFE0FF), opacity: 0.3 * palette.stars)
            var moon = ctx
            moon.opacity = min(1, palette.stars * 1.3)
            moon.fill(Path(ellipseIn: CGRect(x: center.x - 38, y: center.y - 38, width: 76, height: 76)),
                      with: .radialGradient(Gradient(colors: [RGB(0xFFFDF0).color, RGB(0xD8D6C8).color]),
                                            center: CGPoint(x: center.x - 10, y: center.y - 10),
                                            startRadius: 0, endRadius: 46))
            let craters: [(Double, Double, Double)] = [(-12, -8, 9), (10, 6, 12), (-4, 16, 6), (14, -14, 5)]
            for (dx, dy, r) in craters {
                moon.fill(Path(ellipseIn: CGRect(x: center.x + dx - r, y: center.y + dy - r, width: r * 2, height: r * 2)),
                          with: .color(RGB(0xA8A698).withOpacity(0.35)))
            }
        }
    }

    private static func radialGlow(_ ctx: inout GraphicsContext, center: CGPoint, radius: Double, color: RGB, opacity: Double) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [color.withOpacity(opacity), color.withOpacity(opacity * 0.35), color.withOpacity(0)]),
            center: center, startRadius: 0, endRadius: radius
        ))
    }

    /// A mountain or hill silhouette made of layered sine waves.
    private static func drawRidge(
        _ ctx: inout GraphicsContext,
        width: Double,
        offset: Double,
        baseY: Double,
        amplitude: Double,
        frequency: Double,
        seed: Double,
        peaky: Bool,
        top: RGB,
        bottom: RGB
    ) {
        var path = Path()
        path.move(to: CGPoint(x: -20, y: GameWorld.groundY))
        var x = -20.0
        while x <= width + 20 {
            let wx = x + offset
            var n = 0.55 * sin(wx * frequency + seed)
                + 0.3 * sin(wx * frequency * 2.3 + seed * 1.7)
                + 0.15 * sin(wx * frequency * 5.1 + seed * 0.3)
            if peaky {
                // Fold the wave to get sharp mountain tops.
                n = 1 - abs(n) * 1.6
            }
            path.addLine(to: CGPoint(x: x, y: baseY - amplitude * n))
            x += 12
        }
        path.addLine(to: CGPoint(x: width + 20, y: GameWorld.groundY))
        path.closeSubpath()
        ctx.fill(path, with: .linearGradient(
            Gradient(colors: [top.color, bottom.color]),
            startPoint: CGPoint(x: 0, y: baseY - amplitude),
            endPoint: CGPoint(x: 0, y: GameWorld.groundY)
        ))
    }

    private static func drawMist(_ ctx: inout GraphicsContext, palette: SkyPalette, width: Double) {
        let rect = CGRect(x: -20, y: 560, width: width + 40, height: 220)
        ctx.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [palette.horizon.withOpacity(0), palette.horizon.withOpacity(0.35), palette.horizon.withOpacity(0)]),
            startPoint: CGPoint(x: 0, y: rect.minY),
            endPoint: CGPoint(x: 0, y: rect.maxY)
        ))
    }

    private static func drawClouds(_ ctx: inout GraphicsContext, world: GameWorld, palette: SkyPalette) {
        for cloud in world.clouds {
            var puffs = Path()
            let s = cloud.scale
            let lobes = 4 + cloud.seed % 3
            for i in 0..<lobes {
                let fx = Double(i) / Double(lobes - 1) - 0.5
                let r = (34 + hash(cloud.seed + i) * 26) * s * (1 - abs(fx) * 0.6)
                let cx = cloud.x + fx * 150 * s
                let cy = cloud.y - r * 0.45
                puffs.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            }
            puffs.addRoundedRect(in: CGRect(x: cloud.x - 90 * s, y: cloud.y - 22 * s, width: 180 * s, height: 36 * s),
                                 cornerSize: CGSize(width: 18 * s, height: 18 * s))
            let opacity = 0.55 + cloud.depth * 1.3
            // A soft shadow below, then the lit cloud body.
            var shadow = ctx
            shadow.translateBy(x: 0, y: 8 * s)
            shadow.fill(puffs, with: .color(palette.cloud.darker(0.35).mix(palette.top, 0.3).withOpacity(opacity * 0.35)))
            ctx.fill(puffs, with: .linearGradient(
                Gradient(colors: [palette.cloud.withOpacity(opacity), palette.cloud.mix(palette.horizon, 0.35).withOpacity(opacity)]),
                startPoint: CGPoint(x: 0, y: cloud.y - 70 * s),
                endPoint: CGPoint(x: 0, y: cloud.y + 14 * s)
            ))
        }
    }

    private static func drawBushes(_ ctx: inout GraphicsContext, world: GameWorld, palette: SkyPalette, width: Double) {
        func row(spacing: Double, parallax: Double, minR: Double, maxR: Double, seed: Int, color: RGB) {
            let offset = world.distance * parallax
            let first = Int(floor(offset / spacing)) - 2
            let count = Int(width / spacing) + 5
            var path = Path()
            for k in 0..<count {
                let i = first + k
                let x = Double(i) * spacing - offset
                let r = minR + hash(i + seed) * (maxR - minR)
                path.addEllipse(in: CGRect(x: x - r, y: GameWorld.groundY - r * 0.9, width: r * 2, height: r * 2))
            }
            ctx.fill(path, with: .linearGradient(
                Gradient(colors: [color.lighter(0.18).color, color.darker(0.25).color]),
                startPoint: CGPoint(x: 0, y: GameWorld.groundY - maxR * 1.9),
                endPoint: CGPoint(x: 0, y: GameWorld.groundY)
            ))
        }
        row(spacing: 64, parallax: 0.4, minR: 34, maxR: 58, seed: 0, color: palette.bush.darker(0.15))
        row(spacing: 52, parallax: 0.55, minR: 22, maxR: 40, seed: 77, color: palette.bush)
    }

    // MARK: - Foreground

    private static func drawPipe(_ ctx: inout GraphicsContext, pipe: GameWorld.Pipe, world: GameWorld) {
        let w = world.pipeWidth
        let capH = world.pipeCapHeight
        let capW = w + 18
        let base = RGB(0x5BBF3A)
        let dark = RGB(0x2E7A1E)
        let light = RGB(0xC2F58A)
        let outline = RGB(0x1E4A12)

        let bodyGradient = Gradient(stops: [
            .init(color: dark.color, location: 0),
            .init(color: base.color, location: 0.12),
            .init(color: light.color, location: 0.3),
            .init(color: base.color, location: 0.55),
            .init(color: dark.color, location: 0.88),
            .init(color: dark.darker(0.25).color, location: 1),
        ])

        let topBody = CGRect(x: pipe.x - w / 2, y: -30, width: w, height: pipe.gapTop - capH + 30)
        let topCap = CGRect(x: pipe.x - capW / 2, y: pipe.gapTop - capH, width: capW, height: capH)
        let bottomCap = CGRect(x: pipe.x - capW / 2, y: pipe.gapBottom, width: capW, height: capH)
        let bottomBody = CGRect(x: pipe.x - w / 2, y: pipe.gapBottom + capH,
                                width: w, height: GameWorld.groundY - pipe.gapBottom - capH + 4)

        // Drop shadow.
        for rect in [topBody, bottomBody, topCap, bottomCap] {
            ctx.fill(Path(roundedRect: rect.offsetBy(dx: 10, dy: 0), cornerRadius: 6),
                     with: .color(.black.opacity(0.16)))
        }

        for (body, cap, capEdgeY) in [(topBody, topCap, topCap.minY), (bottomBody, bottomCap, bottomCap.maxY)] {
            if body.height > 0 {
                let bodyPath = Path(body)
                ctx.fill(bodyPath, with: .linearGradient(bodyGradient,
                                                         startPoint: CGPoint(x: body.minX, y: 0),
                                                         endPoint: CGPoint(x: body.maxX, y: 0)))
                // Shading where the body meets the cap.
                let shadeY = capEdgeY == cap.minY ? cap.minY - 14 : cap.maxY
                ctx.fill(Path(CGRect(x: body.minX, y: shadeY, width: body.width, height: 14)),
                         with: .color(.black.opacity(0.18)))
                ctx.fill(Path(CGRect(x: body.minX + w * 0.22, y: body.minY, width: 7, height: body.height)),
                         with: .color(.white.opacity(0.3)))
                ctx.stroke(bodyPath, with: .color(outline.color), lineWidth: 4)
            }

            let capPath = Path(roundedRect: cap, cornerRadius: 7)
            ctx.fill(capPath, with: .linearGradient(bodyGradient,
                                                    startPoint: CGPoint(x: cap.minX, y: 0),
                                                    endPoint: CGPoint(x: cap.maxX, y: 0)))
            ctx.fill(Path(CGRect(x: cap.minX + capW * 0.2, y: cap.minY + 5, width: 8, height: cap.height - 10)),
                     with: .color(.white.opacity(0.4)))
            ctx.fill(Path(CGRect(x: cap.minX + 4, y: cap.minY + 4, width: cap.width - 8, height: 5)),
                     with: .color(.white.opacity(0.18)))
            ctx.stroke(capPath, with: .color(outline.color), lineWidth: 4.5)
        }
    }

    private static func drawGround(_ ctx: inout GraphicsContext, world: GameWorld, width: Double) {
        let gy = GameWorld.groundY
        let offset = world.distance
        let groundRect = CGRect(x: -30, y: gy, width: width + 60, height: GameWorld.groundHeight + 40)

        // Dirt.
        ctx.fill(Path(groundRect), with: .linearGradient(
            Gradient(colors: [RGB(0xE3C987).color, RGB(0xC49A57).color, RGB(0x9C7240).color]),
            startPoint: CGPoint(x: 0, y: gy),
            endPoint: CGPoint(x: 0, y: GameWorld.height)
        ))

        // Pebbles.
        var pebbles = Path()
        let pebbleSpacing = 37.0
        let firstPebble = Int(floor(offset / pebbleSpacing)) - 1
        for k in 0..<(Int(width / pebbleSpacing) + 3) {
            let i = firstPebble + k
            let x = Double(i) * pebbleSpacing - offset + hash(i + 40) * 20
            let y = gy + 48 + hash(i + 80) * 80
            let r = 3 + hash(i + 120) * 5
            pebbles.addEllipse(in: CGRect(x: x - r, y: y - r * 0.6, width: r * 2, height: r * 1.2))
        }
        ctx.fill(pebbles, with: .color(RGB(0x7A5530).withOpacity(0.35)))

        // Grass band with scrolling diagonal stripes.
        let band = CGRect(x: -30, y: gy, width: width + 60, height: 30)
        ctx.fill(Path(band), with: .linearGradient(
            Gradient(colors: [RGB(0xA8EC62).color, RGB(0x6CBF34).color]),
            startPoint: CGPoint(x: 0, y: band.minY),
            endPoint: CGPoint(x: 0, y: band.maxY)
        ))
        var stripes = Path()
        let stripeSpacing = 36.0
        var sx = -stripeSpacing * 2 - offset.truncatingRemainder(dividingBy: stripeSpacing)
        while sx < width + stripeSpacing {
            stripes.move(to: CGPoint(x: sx, y: band.minY))
            stripes.addLine(to: CGPoint(x: sx + 18, y: band.minY))
            stripes.addLine(to: CGPoint(x: sx + 18 + 20, y: band.maxY))
            stripes.addLine(to: CGPoint(x: sx + 20, y: band.maxY))
            stripes.closeSubpath()
            sx += stripeSpacing
        }
        var stripeLayer = ctx
        stripeLayer.clip(to: Path(band))
        stripeLayer.fill(stripes, with: .color(RGB(0xC9F58E).withOpacity(0.45)))

        // Tufts along the top edge.
        var tufts = Path()
        let tuftSpacing = 22.0
        var tx = -tuftSpacing - offset.truncatingRemainder(dividingBy: tuftSpacing)
        while tx < width + tuftSpacing {
            tufts.addEllipse(in: CGRect(x: tx - 13, y: gy - 9, width: 26, height: 20))
            tx += tuftSpacing
        }
        ctx.fill(tufts, with: .color(RGB(0xA8EC62).color))

        // Edges.
        ctx.fill(Path(CGRect(x: -30, y: band.maxY, width: width + 60, height: 6)),
                 with: .color(RGB(0x4E8A26).color))
        ctx.fill(Path(CGRect(x: -30, y: band.maxY + 6, width: width + 60, height: 10)),
                 with: .color(.black.opacity(0.12)))
    }

    private static func drawBirdShadow(_ ctx: inout GraphicsContext, world: GameWorld) {
        let height = max(0, GameWorld.groundY - world.birdY)
        let closeness = max(0, 1 - height / 700)
        let w = 30 + 40 * closeness
        ctx.fill(Path(ellipseIn: CGRect(x: world.birdX - w / 2, y: GameWorld.groundY + 2, width: w, height: 10)),
                 with: .color(.black.opacity(0.08 + 0.2 * closeness)))
    }

    private static func drawBird(_ context: inout GraphicsContext, world: GameWorld) {
        var ctx = context
        ctx.translateBy(x: world.birdX, y: world.birdY)
        ctx.rotate(by: .radians(world.birdTilt))

        let outline = RGB(0x4A2C05).color

        // Tail feathers.
        var tail = Path()
        tail.move(to: CGPoint(x: -28, y: -8))
        tail.addQuadCurve(to: CGPoint(x: -54, y: -18), control: CGPoint(x: -44, y: -6))
        tail.addQuadCurve(to: CGPoint(x: -48, y: 0), control: CGPoint(x: -56, y: -8))
        tail.addQuadCurve(to: CGPoint(x: -56, y: 12), control: CGPoint(x: -50, y: 6))
        tail.addQuadCurve(to: CGPoint(x: -26, y: 10), control: CGPoint(x: -40, y: 16))
        tail.closeSubpath()
        ctx.fill(tail, with: .linearGradient(
            Gradient(colors: [RGB(0xFFB23F).color, RGB(0xE0771A).color]),
            startPoint: CGPoint(x: -26, y: -18), endPoint: CGPoint(x: -56, y: 12)
        ))
        ctx.stroke(tail, with: .color(outline), lineWidth: 3)

        // Body.
        let body = Path(ellipseIn: CGRect(x: -36, y: -29, width: 72, height: 58))
        ctx.fill(body, with: .radialGradient(
            Gradient(colors: [RGB(0xFFF4A8).color, RGB(0xFFCB2E).color, RGB(0xF09410).color]),
            center: CGPoint(x: -10, y: -14), startRadius: 2, endRadius: 54
        ))
        var belly = ctx
        belly.clip(to: body)
        belly.fill(Path(ellipseIn: CGRect(x: -18, y: 2, width: 46, height: 30)),
                   with: .color(RGB(0xFFF7DA).withOpacity(0.9)))
        ctx.stroke(body, with: .color(outline), lineWidth: 3.5)

        // Cheek.
        ctx.fill(Path(ellipseIn: CGRect(x: 4, y: 3, width: 15, height: 9)),
                 with: .color(RGB(0xFF6F6F).withOpacity(0.45)))

        // Eye.
        let eye = Path(ellipseIn: CGRect(x: 5, y: -25, width: 27, height: 27))
        ctx.fill(eye, with: .color(.white))
        ctx.stroke(eye, with: .color(outline), lineWidth: 3)
        if world.isDead {
            var cross = Path()
            cross.move(to: CGPoint(x: 12, y: -18))
            cross.addLine(to: CGPoint(x: 25, y: -5))
            cross.move(to: CGPoint(x: 25, y: -18))
            cross.addLine(to: CGPoint(x: 12, y: -5))
            ctx.stroke(cross, with: .color(outline), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        } else {
            ctx.fill(Path(ellipseIn: CGRect(x: 15, y: -18, width: 12, height: 13)),
                     with: .color(RGB(0x1A1410).color))
            ctx.fill(Path(ellipseIn: CGRect(x: 19, y: -17, width: 5, height: 5)),
                     with: .color(.white))
        }

        // Beak.
        var upperBeak = Path()
        upperBeak.move(to: CGPoint(x: 22, y: -4))
        upperBeak.addQuadCurve(to: CGPoint(x: 54, y: 3), control: CGPoint(x: 46, y: -9))
        upperBeak.addLine(to: CGPoint(x: 24, y: 7))
        upperBeak.closeSubpath()
        var lowerBeak = Path()
        lowerBeak.move(to: CGPoint(x: 24, y: 7))
        lowerBeak.addLine(to: CGPoint(x: 50, y: 7))
        lowerBeak.addQuadCurve(to: CGPoint(x: 24, y: 17), control: CGPoint(x: 44, y: 16))
        lowerBeak.closeSubpath()
        ctx.fill(lowerBeak, with: .color(RGB(0xE2531A).color))
        ctx.stroke(lowerBeak, with: .color(outline), lineWidth: 3)
        ctx.fill(upperBeak, with: .linearGradient(
            Gradient(colors: [RGB(0xFFB050).color, RGB(0xFF7A1A).color]),
            startPoint: CGPoint(x: 30, y: -6), endPoint: CGPoint(x: 30, y: 7)
        ))
        ctx.stroke(upperBeak, with: .color(outline), lineWidth: 3)

        // Wing, which rotates around the shoulder.
        var wing = ctx
        wing.translateBy(x: -6, y: 4)
        wing.rotate(by: .radians(world.wingAngle))
        var wingPath = Path()
        wingPath.move(to: CGPoint(x: 4, y: -4))
        wingPath.addQuadCurve(to: CGPoint(x: -34, y: -2), control: CGPoint(x: -14, y: -18))
        wingPath.addQuadCurve(to: CGPoint(x: -24, y: 6), control: CGPoint(x: -34, y: 6))
        wingPath.addQuadCurve(to: CGPoint(x: -28, y: 13), control: CGPoint(x: -22, y: 10))
        wingPath.addQuadCurve(to: CGPoint(x: 4, y: 6), control: CGPoint(x: -10, y: 18))
        wingPath.closeSubpath()
        wing.fill(wingPath, with: .linearGradient(
            Gradient(colors: [RGB(0xFFFFFF).color, RGB(0xFFE27A).color]),
            startPoint: CGPoint(x: 0, y: -14), endPoint: CGPoint(x: 0, y: 14)
        ))
        wing.stroke(wingPath, with: .color(outline), lineWidth: 3)
    }

    private static func drawParticles(_ ctx: inout GraphicsContext, world: GameWorld) {
        for p in world.particles {
            let fade = 1 - p.progress
            switch p.kind {
            case .feather:
                var f = ctx
                f.translateBy(x: p.x, y: p.y)
                f.rotate(by: .radians(p.rotation))
                f.opacity = min(1, fade * 1.5)
                let rect = CGRect(x: -12 * p.size, y: -4.5 * p.size, width: 24 * p.size, height: 9 * p.size)
                f.fill(Path(ellipseIn: rect), with: .color(RGB(0xFFD24A).color))
                f.stroke(Path(ellipseIn: rect), with: .color(RGB(0xB8741A).color), lineWidth: 1.5)
                var quill = Path()
                quill.move(to: CGPoint(x: rect.minX + 2, y: 0))
                quill.addLine(to: CGPoint(x: rect.maxX - 2, y: 0))
                f.stroke(quill, with: .color(RGB(0xFFF6D0).color), lineWidth: 1.5)
            case .puff:
                let r = p.size * (0.6 + p.progress * 1.2)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.55 * fade)))
            case .dust:
                let r = p.size * (0.6 + p.progress)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(RGB(0xE8D3A0).withOpacity(0.7 * fade)))
            case .spark:
                var s = ctx
                s.translateBy(x: p.x, y: p.y)
                s.rotate(by: .radians(p.rotation))
                s.fill(starPath(radius: p.size * (0.5 + fade * 0.5), inner: 0.3),
                       with: .color(RGB(0xFFF3A0).withOpacity(fade)))
            }
        }
    }

    // MARK: - HUD

    private static func drawHUD(_ ctx: inout GraphicsContext, world: GameWorld, width: Double) {
        let cx = width / 2
        switch world.phase {
        case .ready:
            drawTitle(&ctx, world: world, width: width)
        case .playing, .dying:
            label(&ctx, "\(world.score)", size: 104 * (1 + world.scorePulse * 0.25),
                  at: CGPoint(x: cx, y: 120))
        case .gameOver:
            drawGameOver(&ctx, world: world, width: width)
        }

        // Hinge readout on the ground, so you can see that hinge data arrives.
        let hingeText = world.hingeAngle.map { "Hinge \(Int($0.rounded()))°" } ?? "No hinge data"
        ctx.draw(Text(hingeText).font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(RGB(0x5A3A10).withOpacity(0.7)),
                 at: CGPoint(x: cx, y: GameWorld.groundY + 90), anchor: .center)
    }

    private static func drawTitle(_ ctx: inout GraphicsContext, world: GameWorld, width: Double) {
        let cx = width / 2
        let bob = sin(world.clock * 2) * 6
        label(&ctx, "Folding", size: 76, at: CGPoint(x: cx, y: 165 + bob))
        label(&ctx, "Flappy", size: 92, at: CGPoint(x: cx, y: 250 + bob), fill: RGB(0xFFD34A))

        drawFoldIcon(&ctx, center: CGPoint(x: cx, y: 640), time: world.clock)
        label(&ctx, "Close & open to flap", size: 34, at: CGPoint(x: cx, y: 745))
        label(&ctx, "or tap the screen", size: 24, at: CGPoint(x: cx, y: 790), fill: RGB(0xFFF3D6))

        if world.best > 0 {
            label(&ctx, "Best \(world.best)", size: 28, at: CGPoint(x: cx, y: 320 + bob), fill: RGB(0xFFF3D6))
        }
    }

    /// A small animated Duo that closes and opens like a book.
    private static func drawFoldIcon(_ ctx: inout GraphicsContext, center: CGPoint, time: Double) {
        let openness = 0.5 + 0.5 * sin(time * 3)
        let panelW = 54.0
        let panelH = 100.0
        let hingeX = center.x
        let top = center.y - panelH / 2

        let left = CGRect(x: hingeX - panelW, y: top, width: panelW, height: panelH)
        drawDevicePanel(&ctx, rect: left, screen: RGB(0x7FD3FF), shade: 0)

        // The right panel swings over the hinge. Its projected width is cos(angle).
        let angle = (1 - openness) * .pi
        let projected = panelW * cos(angle)
        let rect = CGRect(x: min(hingeX, hingeX + projected), y: top, width: max(abs(projected), 2), height: panelH)
        let showsBack = projected < 0
        drawDevicePanel(&ctx, rect: rect,
                        screen: showsBack ? RGB(0x2A2F3A) : RGB(0x9FE0FF),
                        shade: 1 - abs(cos(angle)))

        ctx.fill(Path(CGRect(x: hingeX - 2, y: top - 2, width: 4, height: panelH + 4)),
                 with: .color(RGB(0x15181E).color))
    }

    private static func drawDevicePanel(_ ctx: inout GraphicsContext, rect: CGRect, screen: RGB, shade: Double) {
        let frame = Path(roundedRect: rect, cornerRadius: min(12, rect.width / 2))
        ctx.fill(frame, with: .color(RGB(0x2B303B).color))
        let inset = rect.insetBy(dx: min(5, rect.width / 3), dy: 6)
        if inset.width > 1 {
            ctx.fill(Path(roundedRect: inset, cornerRadius: min(8, inset.width / 2)),
                     with: .linearGradient(Gradient(colors: [screen.lighter(0.3).color, screen.color]),
                                           startPoint: CGPoint(x: inset.minX, y: inset.minY),
                                           endPoint: CGPoint(x: inset.maxX, y: inset.maxY)))
        }
        ctx.fill(frame, with: .color(.black.opacity(shade * 0.35)))
        ctx.stroke(frame, with: .color(.white.opacity(0.6)), lineWidth: 3)
    }

    private static func drawGameOver(_ ctx: inout GraphicsContext, world: GameWorld, width: Double) {
        let cx = width / 2
        let t = min(world.phaseTime / 0.55, 1)
        let ease = 1 - pow(1 - t, 3)
        let slide = (1 - ease) * 500

        var hud = ctx
        hud.opacity = min(1, world.phaseTime * 3)
        label(&hud, "Game Over", size: 78, at: CGPoint(x: cx, y: 225 - (1 - ease) * 60), fill: RGB(0xFF8A3D))

        let panelW = min(width - 48, 460)
        let panel = CGRect(x: cx - panelW / 2, y: 310 + slide, width: panelW, height: 230)
        let panelPath = Path(roundedRect: panel, cornerRadius: 28)
        hud.fill(Path(roundedRect: panel.offsetBy(dx: 0, dy: 10), cornerRadius: 28),
                 with: .color(.black.opacity(0.2)))
        hud.fill(panelPath, with: .linearGradient(
            Gradient(colors: [RGB(0xFFF8E4).color, RGB(0xF5DFA8).color]),
            startPoint: CGPoint(x: 0, y: panel.minY), endPoint: CGPoint(x: 0, y: panel.maxY)
        ))
        hud.stroke(panelPath, with: .color(RGB(0x8A5A20).color), lineWidth: 6)

        // Medal.
        let medalCenter = CGPoint(x: panel.minX + min(100, panelW * 0.24), y: panel.midY + 6)
        drawMedal(&hud, center: medalCenter, score: world.score, time: world.clock)
        hud.draw(Text("MEDAL").font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(RGB(0xC4762A).color),
                 at: CGPoint(x: medalCenter.x, y: panel.minY + 30), anchor: .center)

        // Score and best.
        let columnX = panel.maxX - min(110, panelW * 0.26)
        let caption = Font.system(size: 22, weight: .heavy, design: .rounded)
        let value = Font.system(size: 54, weight: .black, design: .rounded)
        let brown = RGB(0x5A3A10).color
        hud.draw(Text("SCORE").font(caption).foregroundStyle(RGB(0xC4762A).color),
                 at: CGPoint(x: columnX, y: panel.minY + 34), anchor: .center)
        hud.draw(Text("\(world.score)").font(value).foregroundStyle(brown),
                 at: CGPoint(x: columnX, y: panel.minY + 80), anchor: .center)
        hud.draw(Text("BEST").font(caption).foregroundStyle(RGB(0xC4762A).color),
                 at: CGPoint(x: columnX, y: panel.minY + 134), anchor: .center)
        hud.draw(Text("\(world.best)").font(value).foregroundStyle(brown),
                 at: CGPoint(x: columnX, y: panel.minY + 180), anchor: .center)

        if world.isNewBest {
            let badge = CGRect(x: columnX - 104, y: panel.minY + 164, width: 56, height: 30)
            hud.fill(Path(roundedRect: badge, cornerRadius: 10), with: .color(RGB(0xFF4F5E).color))
            hud.draw(Text("NEW").font(.system(size: 18, weight: .black, design: .rounded)).foregroundStyle(.white),
                     at: CGPoint(x: badge.midX, y: badge.midY), anchor: .center)
        }

        if world.canRestart {
            var prompt = ctx
            prompt.opacity = 0.6 + 0.4 * sin(world.clock * 5)
            drawFoldIcon(&prompt, center: CGPoint(x: cx, y: 660), time: world.clock)
            label(&prompt, "Fold to play again", size: 34, at: CGPoint(x: cx, y: 765))
        }
    }

    private static func drawMedal(_ ctx: inout GraphicsContext, center: CGPoint, score: Int, time: Double) {
        let radius = 46.0
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let color: RGB?
        switch score {
        case 40...: color = RGB(0xE8F6FF)
        case 30..<40: color = RGB(0xFFD34A)
        case 20..<30: color = RGB(0xD5DCE6)
        case 10..<20: color = RGB(0xE0975A)
        default: color = nil
        }

        guard let color else {
            ctx.fill(Path(ellipseIn: rect), with: .color(RGB(0xE6D29E).color))
            ctx.stroke(Path(ellipseIn: rect), with: .color(RGB(0xC9AE70).color), lineWidth: 4)
            return
        }

        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [color.lighter(0.6).color, color.color, color.darker(0.3).color]),
            center: CGPoint(x: center.x - 14, y: center.y - 14), startRadius: 0, endRadius: radius * 1.3
        ))
        let inner = rect.insetBy(dx: 10, dy: 10)
        ctx.stroke(Path(ellipseIn: inner), with: .color(color.darker(0.25).withOpacity(0.6)), lineWidth: 3)
        ctx.stroke(Path(ellipseIn: rect), with: .color(color.darker(0.45).color), lineWidth: 4)

        var star = ctx
        star.translateBy(x: center.x, y: center.y)
        star.fill(starPath(radius: 22, inner: 0.45, points: 5), with: .color(color.darker(0.2).withOpacity(0.8)))

        // A sparkle that circles the medal.
        let angle = time * 1.6
        var sparkle = ctx
        sparkle.translateBy(x: center.x + cos(angle) * (radius - 8), y: center.y + sin(angle) * (radius - 8))
        sparkle.rotate(by: .radians(time * 3))
        sparkle.fill(starPath(radius: 10 + 3 * sin(time * 8), inner: 0.25), with: .color(.white))
    }

    // MARK: - Overlays

    private static func drawVignette(_ ctx: inout GraphicsContext, width: Double) {
        let rect = CGRect(x: 0, y: 0, width: width, height: GameWorld.height)
        let center = CGPoint(x: width / 2, y: GameWorld.height / 2)
        let radius = hypot(width, GameWorld.height) / 2
        ctx.fill(Path(rect), with: .radialGradient(
            Gradient(stops: [
                .init(color: .black.opacity(0), location: 0.55),
                .init(color: .black.opacity(0.28), location: 1),
            ]),
            center: center, startRadius: 0, endRadius: radius
        ))
    }

    // MARK: - Helpers

    /// Big rounded text with a dark outline and a drop shadow.
    private static func label(
        _ ctx: inout GraphicsContext,
        _ string: String,
        size: Double,
        at point: CGPoint,
        fill: RGB = .white
    ) {
        let font = Font.system(size: size, weight: .black, design: .rounded)
        let outline = ctx.resolve(Text(string).font(font).foregroundStyle(RGB(0x3B2508).color))
        let shadow = ctx.resolve(Text(string).font(font).foregroundStyle(Color.black.opacity(0.3)))
        let body = ctx.resolve(Text(string).font(font).foregroundStyle(fill.color))

        ctx.draw(shadow, at: CGPoint(x: point.x, y: point.y + size * 0.09), anchor: .center)
        let stroke = max(2, size * 0.045)
        for i in 0..<8 {
            let a = Double(i) / 8 * 2 * .pi
            ctx.draw(outline, at: CGPoint(x: point.x + cos(a) * stroke, y: point.y + sin(a) * stroke), anchor: .center)
        }
        ctx.draw(body, at: point, anchor: .center)
    }

    private static func starPath(radius: Double, inner: Double, points: Int = 4) -> Path {
        var path = Path()
        let count = points * 2
        for i in 0..<count {
            let r = i.isMultiple(of: 2) ? radius : radius * inner
            let a = Double(i) / Double(count) * 2 * .pi - .pi / 2
            let point = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    /// A stable pseudo random number from 0 to 1 for an index.
    private static func hash(_ n: Int) -> Double {
        let x = sin(Double(n) * 127.1 + 311.7) * 43_758.5453
        return x - floor(x)
    }
}
