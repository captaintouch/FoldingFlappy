import CoreGraphics
import Foundation

/// The game simulation. It has no SwiftUI state, so the renderer can advance
/// it from inside a `Canvas` without triggering view updates.
///
/// Units are world points. The world is always 1000 points tall and as wide as
/// the aspect ratio of the screen. When you fold or unfold the Duo, the world
/// gets narrower or wider while you play.
final class GameWorld {
    enum Phase {
        case ready
        case playing
        case dying
        case gameOver
    }

    struct Pipe {
        var x: Double
        var gapY: Double
        var gap: Double
        var scored = false

        var gapTop: Double { gapY - gap / 2 }
        var gapBottom: Double { gapY + gap / 2 }
    }

    enum ParticleKind {
        case feather
        case puff
        case spark
        case dust
    }

    struct Particle {
        var kind: ParticleKind
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var gravity: Double
        var life: Double
        var maxLife: Double
        var size: Double
        var rotation: Double
        var spin: Double

        /// 0 when the particle is new, 1 when it is at the end of its life.
        var progress: Double { 1 - life / maxLife }
    }

    struct Cloud {
        var x: Double
        var y: Double
        var scale: Double
        var depth: Double
        var seed: Int
    }

    // MARK: - Tuning

    static let height: Double = 1000
    static let groundHeight: Double = 140
    static let groundY: Double = height - groundHeight
    static let dayLength: Double = 100

    let gravity: Double = 2450
    let flapVelocity: Double = -760
    let maxFallSpeed: Double = 1150
    let scrollSpeed: Double = 260
    let pipeWidth: Double = 124
    let pipeCapHeight: Double = 48
    let pipeSpacing: Double = 400
    let birdRadius: Double = 27

    // MARK: - State

    private(set) var width: Double = 560
    private(set) var phase: Phase = .ready
    private(set) var phaseTime: Double = 0
    private(set) var score = 0
    private(set) var best: Int
    private(set) var isNewBest = false
    private(set) var birdX: Double = 170
    private(set) var birdY: Double = 430
    private(set) var birdVelocity: Double = 0
    private(set) var wingPhase: Double = 0
    private(set) var pipes: [Pipe] = []
    private(set) var particles: [Particle] = []
    private(set) var clouds: [Cloud] = []
    /// Total distance the world scrolled. Drives all parallax layers.
    private(set) var distance: Double = 0
    /// Total time since launch. Drives the day and night cycle.
    private(set) var clock: Double = 0
    private(set) var shake: Double = 0
    private(set) var flash: Double = 0
    private(set) var scorePulse: Double = 0

    /// The hinge angle of the Duo in degrees (0 closed, 180 flat), or nil
    /// when the device sends no hinge data.
    var hingeAngle: Double?

    private var flapBoost: Double = 0
    private var lastDate: Date?

    private static let bestKey = "FoldingFlappy.best"

    init() {
        best = UserDefaults.standard.integer(forKey: Self.bestKey)
        for i in 0..<8 {
            clouds.append(makeCloud(x: Double(i) * 170 + .random(in: 0...80)))
        }
    }

    // MARK: - Derived values

    /// Time of day from 0 to 1. 0 is morning, 0.6 is night.
    var dayProgress: Double {
        (clock / Self.dayLength + 0.05).truncatingRemainder(dividingBy: 1)
    }

    /// Rotation of the bird in radians.
    var birdTilt: Double {
        switch phase {
        case .ready:
            return sin(clock * 3.2) * 0.08
        case .playing, .dying, .gameOver:
            return min(max(birdVelocity / 1000 * 1.3, -0.45), 1.45)
        }
    }

    /// Rotation of the wing in radians.
    var wingAngle: Double {
        switch phase {
        case .ready, .playing:
            if let hingeAngle {
                // The wing follows the hinge: open phone is wing up,
                // closed phone is wing down.
                return -0.7 + min(max(hingeAngle, 0), 180) / 180 * 1.6
            }
            return sin(wingPhase) * 0.75
        case .dying, .gameOver:
            return -0.4
        }
    }

    var isDead: Bool { phase == .dying || phase == .gameOver }

    var canRestart: Bool { phase == .gameOver && phaseTime > 0.8 }

    // MARK: - Input

    /// Makes the bird flap. Also starts and restarts the game.
    /// - Returns: `true` when the flap had an effect.
    @discardableResult
    func flap() -> Bool {
        switch phase {
        case .ready:
            phase = .playing
            phaseTime = 0
            applyFlap()
            return true
        case .playing:
            applyFlap()
            return true
        case .dying:
            return false
        case .gameOver:
            guard canRestart else { return false }
            reset()
            return true
        }
    }

    private func applyFlap() {
        birdVelocity = flapVelocity
        flapBoost = 1
        emit(.puff, count: 5, x: birdX - 20, y: birdY + 18,
             speed: 60...160, angle: (Double.pi * 0.55)...(Double.pi * 0.95),
             life: 0.35...0.6, size: 10...18, gravity: -60)
        if Double.random(in: 0...1) < 0.35 {
            emit(.feather, count: 1, x: birdX - 14, y: birdY + 4,
                 speed: 60...140, angle: (Double.pi * 0.6)...(Double.pi * 0.9),
                 life: 0.9...1.4, size: 0.8...1.1, gravity: 180)
        }
    }

    private func reset() {
        phase = .ready
        phaseTime = 0
        score = 0
        isNewBest = false
        pipes.removeAll()
        particles.removeAll()
        birdY = 430
        birdVelocity = 0
    }

    // MARK: - Simulation

    /// Moves the simulation forward to `date`.
    func advance(to date: Date, viewport: CGSize) {
        let aspect = Double(viewport.width / viewport.height)
        if aspect.isFinite, aspect > 0 {
            // Clamp, so that a strange size during a layout pass cannot make
            // the world extremely wide.
            width = Self.height * min(max(aspect, 0.2), 4)
        }
        guard let last = lastDate else {
            lastDate = date
            return
        }
        lastDate = date

        // Clamp the step, so that a pause (for example while the Duo is
        // closed) does not make the bird jump.
        let elapsed = min(max(date.timeIntervalSince(last), 0), 1.0 / 20)
        guard elapsed > 0 else { return }
        let steps = max(1, Int((elapsed * 240).rounded(.up)))
        let dt = elapsed / Double(steps)
        for _ in 0..<steps {
            update(dt)
        }
    }

    private func update(_ dt: Double) {
        clock += dt
        phaseTime += dt
        shake = max(0, shake - dt * 2.2)
        flash = max(0, flash - dt * 2.8)
        scorePulse = max(0, scorePulse - dt * 3)
        flapBoost = max(0, flapBoost - dt * 3.5)

        // The bird glides to its new position when the world changes width.
        let targetX = min(max(width * 0.3, 140), 320)
        birdX += (targetX - birdX) * min(1, dt * 5)

        switch phase {
        case .ready:
            distance += scrollSpeed * dt
            birdY = 430 + sin(clock * 3.2) * 16
            birdVelocity = 0
            wingPhase += dt * 11
        case .playing:
            distance += scrollSpeed * dt
            wingPhase += dt * (9 + flapBoost * 26)
            birdVelocity = min(birdVelocity + gravity * dt, maxFallSpeed)
            birdY += birdVelocity * dt
            if birdY < birdRadius {
                birdY = birdRadius
                birdVelocity = max(0, birdVelocity)
            }
            updatePipes(dt)
            checkCollisions()
        case .dying:
            birdVelocity = min(birdVelocity + gravity * 1.1 * dt, maxFallSpeed * 1.2)
            birdY += birdVelocity * dt
            if birdY >= Self.groundY - birdRadius {
                birdY = Self.groundY - birdRadius
                enterGameOver()
            }
        case .gameOver:
            break
        }

        updateClouds(dt)
        updateParticles(dt)
    }

    private func updatePipes(_ dt: Double) {
        for i in pipes.indices {
            pipes[i].x -= scrollSpeed * dt
            if !pipes[i].scored && pipes[i].x < birdX {
                pipes[i].scored = true
                score += 1
                scorePulse = 1
                emit(.spark, count: 12, x: pipes[i].x, y: pipes[i].gapY,
                     speed: 120...320, angle: 0...(2 * Double.pi),
                     life: 0.4...0.8, size: 8...16, gravity: 0)
            }
        }
        pipes.removeAll { $0.x < -pipeWidth * 2 }
        spawnPipesIfNeeded()
    }

    private func spawnPipesIfNeeded() {
        var nextX = pipes.last.map { $0.x + pipeSpacing } ?? (width + pipeWidth)
        while nextX <= width + pipeWidth * 2 {
            // The gap gets smaller as the score goes up.
            let gap = max(215, 290 - Double(score) * 2.5)
            let minY = 150 + gap / 2
            let maxY = Self.groundY - 110 - gap / 2
            var gapY = Double.random(in: minY...maxY)
            if let previous = pipes.last?.gapY {
                gapY = min(max(gapY, previous - 280), previous + 280)
            }
            pipes.append(Pipe(x: nextX, gapY: gapY, gap: gap))
            nextX += pipeSpacing
        }
    }

    private func checkCollisions() {
        let radius = birdRadius * 0.86
        if birdY + radius >= Self.groundY {
            die()
            return
        }
        for pipe in pipes {
            let minX = pipe.x - pipeWidth / 2
            let maxX = pipe.x + pipeWidth / 2
            if circleHits(minX: minX, maxX: maxX, minY: -10_000, maxY: pipe.gapTop, radius: radius)
                || circleHits(minX: minX, maxX: maxX, minY: pipe.gapBottom, maxY: 10_000, radius: radius) {
                die()
                return
            }
        }
    }

    private func circleHits(minX: Double, maxX: Double, minY: Double, maxY: Double, radius: Double) -> Bool {
        let nearestX = min(max(birdX, minX), maxX)
        let nearestY = min(max(birdY, minY), maxY)
        return hypot(birdX - nearestX, birdY - nearestY) < radius
    }

    private func die() {
        phase = .dying
        phaseTime = 0
        shake = 1
        flash = 1
        birdVelocity = min(birdVelocity, -300)
        emit(.feather, count: 14, x: birdX, y: birdY,
             speed: 120...380, angle: 0...(2 * Double.pi),
             life: 1.0...1.8, size: 0.8...1.3, gravity: 260)
        emit(.spark, count: 10, x: birdX + 20, y: birdY,
             speed: 200...420, angle: 0...(2 * Double.pi),
             life: 0.2...0.45, size: 10...18, gravity: 0)
        if score > best {
            best = score
            isNewBest = true
            UserDefaults.standard.set(best, forKey: Self.bestKey)
        }
    }

    private func enterGameOver() {
        phase = .gameOver
        phaseTime = 0
        shake = max(shake, 0.4)
        emit(.dust, count: 12, x: birdX, y: Self.groundY - 4,
             speed: 60...200, angle: (Double.pi * 1.05)...(Double.pi * 1.95),
             life: 0.5...0.9, size: 10...20, gravity: 120)
    }

    // MARK: - Clouds

    private func makeCloud(x: Double) -> Cloud {
        let depth = Double.random(in: 0.06...0.3)
        return Cloud(
            x: x,
            y: .random(in: 80...420),
            scale: 0.55 + depth * 2.2,
            depth: depth,
            seed: .random(in: 0...9_999)
        )
    }

    private func updateClouds(_ dt: Double) {
        let isScrolling = phase == .ready || phase == .playing
        for i in clouds.indices {
            let speed = (isScrolling ? scrollSpeed * clouds[i].depth : 0) + 6
            clouds[i].x -= speed * dt
            if clouds[i].x < -220 * clouds[i].scale {
                clouds[i] = makeCloud(x: width + 160 + .random(in: 0...220))
            }
        }
    }

    // MARK: - Particles

    private func emit(
        _ kind: ParticleKind,
        count: Int,
        x: Double,
        y: Double,
        speed: ClosedRange<Double>,
        angle: ClosedRange<Double>,
        life: ClosedRange<Double>,
        size: ClosedRange<Double>,
        gravity: Double
    ) {
        for _ in 0..<count {
            let direction = Double.random(in: angle)
            let velocity = Double.random(in: speed)
            let lifetime = Double.random(in: life)
            particles.append(Particle(
                kind: kind,
                x: x,
                y: y,
                vx: cos(direction) * velocity,
                vy: sin(direction) * velocity,
                gravity: gravity,
                life: lifetime,
                maxLife: lifetime,
                size: .random(in: size),
                rotation: .random(in: 0...(2 * Double.pi)),
                spin: .random(in: -6...6)
            ))
        }
    }

    private func updateParticles(_ dt: Double) {
        let drift = phase == .playing ? scrollSpeed * 0.6 : 0
        for i in particles.indices {
            particles[i].life -= dt
            particles[i].vy += particles[i].gravity * dt
            switch particles[i].kind {
            case .feather:
                // Feathers slow down and flutter while they fall.
                particles[i].vx *= max(0, 1 - dt * 1.8)
                particles[i].vy = min(particles[i].vy, 140)
                particles[i].x += sin(clock * 6 + particles[i].rotation) * 40 * dt
            case .puff, .dust:
                particles[i].vx *= max(0, 1 - dt * 3)
                particles[i].vy *= max(0, 1 - dt * 3)
            case .spark:
                particles[i].vx *= max(0, 1 - dt * 4)
                particles[i].vy *= max(0, 1 - dt * 4)
            }
            particles[i].x += (particles[i].vx - drift) * dt
            particles[i].y += particles[i].vy * dt
            particles[i].rotation += particles[i].spin * dt
        }
        particles.removeAll { $0.life <= 0 }
    }
}
