import SwiftUI
import AppKit

enum StageSpace {
    static let name = "paper-stage"
}

// MARK: - Math helpers

func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func easeInOutCubic(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

/// Deterministic noise, so a given paper crumples the same way on every frame.
struct SeededRandom {
    private var state: UInt64

    init(_ seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * unit() }
}

// MARK: - One flying sheet of paper

struct PaperPose {
    /// `loose` papers are drawn in front of the basket (held in hand, or a missed throw).
    /// `shredding` sheets are being pulled into the shredder's slot.
    enum Phase { case crumpling, flying, sinking, bouncing, loose, shredding }

    var center: CGPoint
    var rotation: CGFloat
    var scale: CGFloat
    /// 0 = flat sheet, 1 = tight ball.
    var crumple: CGFloat
    var sheetScale: CGFloat
    var opacity: Double
    var phase: Phase
}

/// Timeline of one file: pops out of its row, gets crumpled, is thrown in an arc,
/// then either sinks into the basket or (if deleting failed) bounces off the rim.
struct Paper: Identifiable {
    static let liftDuration = 0.18
    static let crumpleStart = 0.12
    static let crumpleEnd = 0.52
    static let sinkDuration = 0.28
    static let bounceDuration = 0.85
    static let liftHeight: CGFloat = 30

    let id = UUID()
    let born: Double
    let origin: CGPoint
    let target: CGPoint
    let flight: Double
    let seed: UInt64
    let icon: NSImage?
    let succeeded: Bool
    let spin: CGFloat
    let tilt: CGFloat
    let bounceDirection: CGFloat

    /// Headed for the shredder: the sheet stays flat and goes into the slot.
    let shred: Bool

    var landTime: Double { Paper.crumpleEnd + flight }
    var lifetime: Double { landTime + (succeeded ? (shred ? Paper.shredDuration : Paper.sinkDuration) : Paper.bounceDuration) }
    static let shredDuration = 0.5

    init(born: Double, origin: CGPoint, basket: BasketGeometry, succeeded: Bool, seed: UInt64, icon: NSImage?,
         shredder: ShredderGeometry? = nil) {
        var rng = SeededRandom(seed)
        let mouth = shredder?.slot ?? basket.mouth
        shred = shredder != nil
        let fromLeft = origin.x < mouth.midX
        if succeeded {
            target = CGPoint(x: mouth.midX + mouth.width * rng.range(-0.18, 0.18), y: mouth.midY + 1)
        } else {
            target = CGPoint(x: fromLeft ? mouth.minX + 4 : mouth.maxX - 4, y: mouth.midY - 3)
        }
        let start = CGPoint(x: origin.x, y: origin.y - Paper.liftHeight)
        let distance = hypot(target.x - start.x, target.y - start.y)

        self.born = born
        self.origin = origin
        self.seed = seed
        self.icon = icon
        self.succeeded = succeeded
        flight = 0.55 + min(0.4, Double(distance) / 2200)
        spin = (rng.unit() < 0.5 ? -1 : 1) * rng.range(2.5, 4.5) * .pi
        tilt = rng.range(-0.16, 0.16)
        bounceDirection = fromLeft ? -1 : 1
    }

    func pose(at elapsed: Double) -> PaperPose {
        let lift = CGFloat(easeOutCubic(clamp01(elapsed / Paper.liftDuration)))
        let crumple = shred ? 0 : CGFloat(easeInOutCubic(clamp01((elapsed - Paper.crumpleStart) / (Paper.crumpleEnd - Paper.crumpleStart))))

        // 1. Pop out of the row and get crumpled (or, for the shredder, stay a flat sheet), with a little wind-up.
        if elapsed < Paper.crumpleEnd {
            let windT = CGFloat(clamp01((elapsed - 0.38) / (Paper.crumpleEnd - 0.38)))
            let wind = sin(windT * .pi) * 8
            let direction: CGFloat = target.x >= origin.x ? 1 : -1
            let shake = CGFloat(sin(elapsed * 46)) * 0.16 * sin(.pi * crumple)
            return PaperPose(
                center: CGPoint(x: origin.x - direction * wind, y: origin.y - Paper.liftHeight * lift + wind * 0.5),
                rotation: tilt * lift + shake,
                scale: 1,
                crumple: crumple,
                sheetScale: 0.55 + 0.45 * lift,
                opacity: 1,
                phase: .crumpling
            )
        }

        // 2. Fly along a parabola into the basket.
        let t = elapsed - Paper.crumpleEnd
        if t < flight {
            let u = CGFloat(t / flight)
            let p0 = CGPoint(x: origin.x, y: origin.y - Paper.liftHeight)
            let p2 = target
            let peakY = max(30, min(p0.y, p2.y) - max(70, abs(p2.x - p0.x) * 0.28))
            let control = CGPoint(x: (p0.x + p2.x) / 2, y: 2 * peakY - (p0.y + p2.y) / 2)
            let inv = 1 - u
            let x = inv * inv * p0.x + 2 * inv * u * control.x + u * u * p2.x
            let y = inv * inv * p0.y + 2 * inv * u * control.y + u * u * p2.y
            return PaperPose(center: CGPoint(x: x, y: y), rotation: shred ? tilt * (1 - u) : tilt + spin * u,
                             scale: 1 - 0.22 * u, crumple: shred ? 0 : 1, sheetScale: 1, opacity: 1, phase: .flying)
        }

        // 3a. Sink into the basket, or get pulled down into the shredder…
        let d = t - flight
        if succeeded && shred {
            let k = CGFloat(easeInOutCubic(clamp01(d / Paper.shredDuration)))
            return PaperPose(center: CGPoint(x: target.x, y: target.y + 44 * k), rotation: 0, scale: 0.78,
                             crumple: 0, sheetScale: 1, opacity: 1, phase: .shredding)
        }
        if succeeded {
            let k = CGFloat(clamp01(d / Paper.sinkDuration))
            return PaperPose(center: CGPoint(x: target.x, y: target.y + 30 * k * k), rotation: tilt + spin + 0.6 * k,
                             scale: 0.78, crumple: 1, sheetScale: 1, opacity: Double(1 - k), phase: .sinking)
        }

        // 3b. …or bounce off the rim and fall away.
        let dt = CGFloat(d)
        let position = CGPoint(x: target.x + bounceDirection * 150 * dt, y: target.y - 230 * dt + 750 * dt * dt)
        return PaperPose(center: position, rotation: tilt + spin - 7 * dt * bounceDirection, scale: 0.78,
                         crumple: 1, sheetScale: 1, opacity: 1 - clamp01((d - 0.35) / 0.45), phase: .bouncing)
    }
}

// MARK: - Throwing by hand

/// A sheet the user is dragging. It crumples in their hand while they line up the throw.
struct HeldPaper {
    let itemID: String
    let grabbedAt: Double
    let origin: CGPoint
    var location: CGPoint
    let seed: UInt64
    let icon: NSImage?
    /// This file can't be deleted right now; the rim glows red as a warning.
    var blocked = false
    /// When ⌥ went down: the shredder is out, so the sheet in hand smooths back out flat.
    var armedAt: Double?

    func crumple(at now: Double) -> CGFloat {
        let c = CGFloat(easeInOutCubic(clamp01((now - grabbedAt - 0.04) / 0.32)))
        guard let armedAt else { return c }
        return c * (1 - CGFloat(easeOutCubic(clamp01((now - armedAt) / 0.18))))
    }

    func pose(at now: Double) -> PaperPose {
        let elapsed = now - grabbedAt
        let follow = CGFloat(easeOutCubic(clamp01(elapsed / 0.14)))
        let grow = CGFloat(easeOutCubic(clamp01(elapsed / 0.18)))
        let c = crumple(at: now)
        let shake = CGFloat(sin(elapsed * 46)) * 0.16 * sin(.pi * c)
        return PaperPose(
            center: CGPoint(x: lerp(origin.x, location.x, follow), y: lerp(origin.y, location.y, follow)),
            rotation: shake, scale: 1, crumple: c, sheetScale: 0.55 + 0.45 * grow, opacity: 1, phase: .loose
        )
    }
}

/// A paper ball the user let go of. Its whole path is worked out at release:
/// straight in, off the rim, or a miss that falls out of the window.
struct TossedPaper: Identifiable {
    enum Kind: Equatable { case make, rim, miss, shred }

    static let gravity: CGFloat = 2200

    let id = UUID()
    let itemID: String
    let born: Double
    let start: CGPoint
    let velocity: CGVector
    let seed: UInt64
    let icon: NSImage?
    let startCrumple: CGFloat
    let kind: Kind
    let impactTime: Double
    let impactPoint: CGPoint
    let direction: CGFloat
    let rebound: CGVector
    var lifetime: Double
    /// Whether deleting worked; nil until the file operation finishes.
    var succeeded: Bool?
    /// For the shredder: when the user confirmed or cancelled (the sheet waits in the slot until then).
    var resolvedAt: Double?

    init(itemID: String, born: Double, start: CGPoint, velocity: CGVector, seed: UInt64, icon: NSImage?,
         startCrumple: CGFloat, basket: BasketGeometry, canvas: CGSize, shredder: ShredderGeometry? = nil) {
        let g = TossedPaper.gravity
        let mouth = basket.mouth
        var kind = Kind.miss
        var impactTime = 0.0
        var impactPoint = start
        var direction: CGFloat = velocity.dx >= 0 ? -1 : 1

        // With the shredder out, a sheet that comes down onto its slot is caught there.
        if let shredder {
            let zone = shredder.catchZone
            if zone.contains(start) {
                kind = .shred
                impactPoint = CGPoint(x: start.x, y: shredder.slot.midY)
            } else {
                let disc = velocity.dy * velocity.dy + 2 * g * (zone.midY - start.y)
                let t = disc >= 0 ? (-velocity.dy + sqrt(disc)) / g : -1
                let x = start.x + velocity.dx * max(0, t)
                if t > 0 && x >= zone.minX && x <= zone.maxX {
                    kind = .shred
                    impactTime = Double(t)
                    impactPoint = CGPoint(x: min(max(x, shredder.slot.minX + 8), shredder.slot.maxX - 8), y: shredder.slot.midY)
                }
            }
        }

        if kind == .shred {
            // caught by the shredder; worked out above
        } else if start.y > mouth.midY && basket.silhouette.contains(start) {
            kind = .make // let go right inside the basket
        } else {
            // When does the ball come back down through the rim's height?
            let disc = velocity.dy * velocity.dy + 2 * g * (mouth.midY - start.y)
            let t = disc >= 0 ? (-velocity.dy + sqrt(disc)) / g : -1
            if t > 0 {
                let x = start.x + velocity.dx * t
                let offset = x - mouth.midX
                if abs(offset) <= mouth.width / 2 - 4 {
                    kind = .make
                    impactPoint = CGPoint(x: x, y: mouth.midY + 1)
                } else if abs(offset) <= mouth.width / 2 + 10 {
                    kind = .rim
                    direction = offset < 0 ? -1 : 1
                    impactPoint = CGPoint(x: x, y: mouth.midY - 3)
                }
                if kind != .miss { impactTime = Double(t) }
            }
        }

        let impactVY = velocity.dy + g * CGFloat(impactTime)
        let rebound = CGVector(dx: direction * (abs(velocity.dx) * 0.35 + 90), dy: -abs(impactVY) * 0.35 - 120)

        func exitTime(from p: CGPoint, _ v: CGVector) -> Double {
            var t = (-v.dy + sqrt(max(0, v.dy * v.dy + 2 * g * (canvas.height + 40 - p.y)))) / g
            if v.dx > 1 { t = min(t, (canvas.width + 40 - p.x) / v.dx) }
            if v.dx < -1 { t = min(t, (p.x + 40) / -v.dx) }
            return min(3, max(0.2, Double(t)))
        }

        self.itemID = itemID
        self.born = born
        self.start = start
        self.velocity = velocity
        self.seed = seed
        self.icon = icon
        self.startCrumple = startCrumple
        self.kind = kind
        self.impactTime = impactTime
        self.impactPoint = impactPoint
        self.direction = direction
        self.rebound = rebound
        switch kind {
        case .make: lifetime = impactTime + Paper.bounceDuration
        case .rim: lifetime = impactTime + exitTime(from: impactPoint, rebound)
        case .miss: lifetime = exitTime(from: start, velocity)
        case .shred: lifetime = 600 // waits in the slot until the user confirms; see `PaperStage.resolveShred`
        }
    }

    func pose(at t: Double) -> PaperPose {
        let g = TossedPaper.gravity
        let crumple = kind == .shred ? startCrumple : min(1, startCrumple + CGFloat(t / 0.18))
        let spin = max(-14, min(14, velocity.dx * 0.006))
        let fade = 1 - clamp01((t - (lifetime - 0.3)) / 0.3)

        func ballistic(_ p: CGPoint, _ v: CGVector, _ s: CGFloat) -> CGPoint {
            CGPoint(x: p.x + v.dx * s, y: p.y + v.dy * s + 0.5 * g * s * s)
        }

        if kind == .miss || t < impactTime {
            return PaperPose(center: ballistic(start, velocity, CGFloat(t)), rotation: spin * CGFloat(t),
                             scale: 1 - 0.2 * CGFloat(clamp01(t / 0.5)), crumple: crumple, sheetScale: 1,
                             opacity: kind == .miss ? fade : 1, phase: kind == .miss ? .loose : .flying)
        }

        let d = CGFloat(t - impactTime)
        let spun = spin * CGFloat(impactTime)
        if kind == .shred {
            let waited = CGFloat((resolvedAt ?? born + t) - born) - CGFloat(impactTime)
            let r = max(0, d - waited)
            switch succeeded {
            case true?:
                let k = CGFloat(easeInOutCubic(clamp01(Double(r) / Paper.shredDuration)))
                return PaperPose(center: CGPoint(x: impactPoint.x, y: impactPoint.y - 10 + 54 * k), rotation: 0, scale: 0.8,
                                 crumple: 0, sheetScale: 1, opacity: 1, phase: .shredding)
            case false?:
                let position = CGPoint(x: impactPoint.x - 120 * r, y: impactPoint.y - 12 - 380 * r + 900 * r * r)
                return PaperPose(center: position, rotation: -3 * r, scale: 0.8, crumple: crumple, sheetScale: 1,
                                 opacity: 1 - clamp01((Double(r) - 0.5) / 0.4), phase: .loose)
            case nil:
                // Held in the jaws, quivering, while the confirmation is up.
                let jiggle = CGFloat(sin(t * 38)) * 1.2
                return PaperPose(center: CGPoint(x: impactPoint.x + jiggle, y: impactPoint.y - 10), rotation: jiggle * 0.01,
                                 scale: 0.8, crumple: crumple, sheetScale: 1, opacity: 1, phase: .shredding)
            }
        }
        if kind == .rim {
            return PaperPose(center: ballistic(impactPoint, rebound, d), rotation: spun - 6 * d * direction,
                             scale: 0.8, crumple: 1, sheetScale: 1, opacity: fade, phase: .loose)
        }
        if succeeded == false {
            let position = CGPoint(x: impactPoint.x + direction * 150 * d, y: impactPoint.y - 230 * d + 750 * d * d)
            return PaperPose(center: position, rotation: spun - 7 * d * direction, scale: 0.78, crumple: 1, sheetScale: 1,
                             opacity: 1 - clamp01((Double(d) - 0.35) / 0.45), phase: .bouncing)
        }
        let k = min(1, d / CGFloat(Paper.sinkDuration))
        return PaperPose(center: CGPoint(x: impactPoint.x, y: impactPoint.y + 30 * k * k), rotation: spun + 0.6 * k,
                         scale: 0.78, crumple: 1, sheetScale: 1, opacity: Double(1 - k), phase: .sinking)
    }
}

// MARK: - Undo

/// A paper ball that jumps back out of the basket and smooths itself flat on the way, for undo.
struct ReturningPaper: Identifiable {
    static let duration = 1.0

    let id = UUID()
    let born: Double
    let start: CGPoint
    let target: CGPoint
    let seed: UInt64
    let icon: NSImage?

    func pose(at t: Double) -> PaperPose {
        let pop = 0.14, land = 0.78
        if t < pop {
            let k = CGFloat(easeOutCubic(t / pop))
            return PaperPose(center: CGPoint(x: start.x, y: start.y - 34 * k), rotation: 0.4 * k, scale: 0.8,
                             crumple: 1, sheetScale: 1, opacity: 1, phase: .loose)
        }
        let p0 = CGPoint(x: start.x, y: start.y - 34)
        if t < land {
            let u = CGFloat((t - pop) / (land - pop))
            let peakY = min(p0.y, target.y) - max(60, abs(target.x - p0.x) * 0.22)
            let control = CGPoint(x: (p0.x + target.x) / 2, y: 2 * peakY - (p0.y + target.y) / 2)
            let inv = 1 - u
            let center = CGPoint(x: inv * inv * p0.x + 2 * inv * u * control.x + u * u * target.x,
                                 y: inv * inv * p0.y + 2 * inv * u * control.y + u * u * target.y)
            let unfold = CGFloat(easeInOutCubic(Double(u)))
            return PaperPose(center: center, rotation: 0.4 + 2.2 * u * (1 - u), scale: 0.8 + 0.3 * unfold,
                             crumple: 1 - unfold, sheetScale: 1, opacity: 1, phase: .loose)
        }
        let k = clamp01((t - land) / (ReturningPaper.duration - land))
        return PaperPose(center: CGPoint(x: target.x, y: target.y - 6 * CGFloat(k)), rotation: 0, scale: 1.1,
                         crumple: 0, sheetScale: 1, opacity: 1 - k, phase: .loose)
    }
}

// MARK: - Stage state

struct StageSnapshot {
    var papers: [Paper] = []
    var tossed: [TossedPaper] = []
    var held: HeldPaper?
    var pileCount = 0
    var lastLanding: Double = -100
    var pileClearedAt: Double?
    var shredderShownAt: Double?
    var shredderHiddenAt: Double?
    var stripCount = 0
    var lastShred: Double?
    var returning: [ReturningPaper] = []
    /// How many balls were in the basket when it was tipped out.
    var poured = 0
}

@MainActor @Observable
final class PaperStage {
    private(set) var papers: [Paper] = []
    private(set) var tossed: [TossedPaper] = []
    private(set) var held: HeldPaper?
    private(set) var isTicking = false
    private(set) var pileCount = 0
    private(set) var lastLanding: Double = -100
    private(set) var pileClearedAt: Double?
    private(set) var shredderShownAt: Double?
    private(set) var shredderHiddenAt: Double?
    private(set) var stripCount = 0
    private(set) var lastShred: Double?
    private(set) var returning: [ReturningPaper] = []
    private(set) var poured = 0

    @ObservationIgnored var canvasSize = CGSize(width: 1080, height: 720)
    @ObservationIgnored private var seed: UInt64 = 0x5EED
    @ObservationIgnored private var tickDeadline: Double = 0

    var snapshot: StageSnapshot {
        StageSnapshot(papers: papers, tossed: tossed, held: held, pileCount: pileCount,
                      lastLanding: lastLanding, pileClearedAt: pileClearedAt,
                      shredderShownAt: shredderShownAt, shredderHiddenAt: shredderHiddenAt,
                      stripCount: stripCount, lastShred: lastShred, returning: returning, poured: poured)
    }

    private var basket: BasketGeometry { BasketGeometry(rect: BasketGeometry.rect(in: canvasSize)) }
    private var shredder: ShredderGeometry { ShredderGeometry(rect: ShredderGeometry.rect(above: basket)) }

    // The shredder

    /// ⌥ held while dragging: bring the shredder out and flatten the sheet. Not for files that can't be deleted.
    func setArmed(_ armed: Bool) {
        guard var paper = held, !paper.blocked else { return }
        let isArmed = paper.armedAt != nil
        guard armed != isArmed else { return }
        paper.armedAt = armed ? Date.timeIntervalSinceReferenceDate : nil
        held = paper
        refreshShredder()
    }

    /// The user confirmed (shredded) or cancelled a sheet waiting in the slot.
    func resolveShred(_ id: UUID, shredded: Bool) {
        guard let i = tossed.firstIndex(where: { $0.id == id }) else { return }
        let now = Date.timeIntervalSinceReferenceDate
        tossed[i].succeeded = shredded
        tossed[i].resolvedAt = now
        tossed[i].lifetime = now - tossed[i].born + (shredded ? Paper.shredDuration + 0.1 : 1.0)
        keepTicking(for: 2.5)
        if shredded { noteShred(after: 0.2) }
        SoundBoard.shared.play(shredded ? .shred : .clank, volume: shredded ? 1 : 0.5)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(shredded ? Paper.shredDuration + 0.1 : 1.0))
            self?.tossed.removeAll { $0.id == id }
            self?.refreshShredder()
        }
    }

    private func noteShred(after delay: Double) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            self.stripCount += 1
            self.lastShred = Date.timeIntervalSinceReferenceDate
        }
    }

    /// Out while it is armed or anything is headed for it; tucked away a moment after the last sheet.
    private func refreshShredder() {
        let now = Date.timeIntervalSinceReferenceDate
        let wanted = held?.armedAt != nil || papers.contains(where: \.shred) || tossed.contains { $0.kind == .shred }
        if wanted {
            if shredderShownAt == nil { shredderShownAt = now }
            shredderHiddenAt = nil
            keepTicking(for: 0.4)
        } else if shredderShownAt != nil && shredderHiddenAt == nil {
            let hideAt = now + 0.9
            shredderHiddenAt = hideAt
            keepTicking(for: 1.3)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                guard let self, self.shredderHiddenAt == hideAt else { return }
                self.shredderShownAt = nil
                self.shredderHiddenAt = nil
            }
        }
    }

    private func nextSeed() -> UInt64 {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return seed
    }

    // Throwing by hand

    func grab(itemID: String, icon: NSImage?, origin: CGPoint, location: CGPoint, blocked: Bool) {
        held = HeldPaper(itemID: itemID, grabbedAt: Date.timeIntervalSinceReferenceDate, origin: origin,
                         location: location, seed: nextSeed(), icon: icon, blocked: blocked)
        isTicking = true
        SoundBoard.shared.play(.crumple, volume: 0.7)
    }

    func moveHeld(to location: CGPoint) {
        held?.location = location
    }

    func release(velocity: CGSize) -> TossedPaper? {
        guard let held else { return nil }
        let now = Date.timeIntervalSinceReferenceDate
        var v = CGVector(dx: velocity.width, dy: velocity.height)
        let speed = hypot(v.dx, v.dy)
        if speed > 3200 {
            v.dx *= 3200 / speed
            v.dy *= 3200 / speed
        }
        let toss = TossedPaper(itemID: held.itemID, born: now, start: held.pose(at: now).center, velocity: v,
                               seed: held.seed, icon: held.icon, startCrumple: held.crumple(at: now),
                               basket: basket, canvas: canvasSize, shredder: held.armedAt != nil ? shredder : nil)
        self.held = nil
        tossed.append(toss)
        refreshShredder()
        // A sheet in the shredder waits for the user; `resolveShred` finishes it.
        guard toss.kind != .shred else {
            keepTicking(for: 600)
            return toss
        }
        keepTicking(for: toss.lifetime + 1.7)

        Task { [weak self] in
            if toss.kind != .miss {
                try? await Task.sleep(for: .seconds(toss.impactTime))
                if let self {
                    let deleted = self.tossed.first { $0.id == toss.id }?.succeeded != false
                    if toss.kind == .make && deleted { self.pileCount += 1 }
                    self.lastLanding = Date.timeIntervalSinceReferenceDate
                    SoundBoard.shared.play(toss.kind == .make && deleted ? .swish : .clank)
                }
            }
            try? await Task.sleep(for: .seconds(toss.lifetime - toss.impactTime))
            self?.tossed.removeAll { $0.id == toss.id }
        }
        return toss
    }

    func settle(_ id: UUID, succeeded: Bool) {
        guard let i = tossed.firstIndex(where: { $0.id == id }) else { return }
        tossed[i].succeeded = succeeded
    }

    // Automatic cleaning

    /// `shred`: the file was deleted for good, so the sheet goes into the shredder instead of the basket.
    func launch(from origin: CGPoint, icon: NSImage?, succeeded: Bool, shred: Bool = false,
                onLand: @escaping @MainActor () -> Void) {
        let paper = Paper(born: Date.timeIntervalSinceReferenceDate, origin: origin, basket: basket,
                          succeeded: succeeded, seed: nextSeed(), icon: icon, shredder: shred ? shredder : nil)
        papers.append(paper)
        refreshShredder()
        keepTicking(for: paper.lifetime + 1.7)

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Paper.crumpleStart))
            if !shred { SoundBoard.shared.play(.crumple, volume: 0.4) }
            try? await Task.sleep(for: .seconds(paper.landTime - Paper.crumpleStart))
            guard let self else { return }
            SoundBoard.shared.play(!succeeded ? .clank : shred ? .shred : .swish, volume: 0.7)
            if succeeded && !shred { self.pileCount += 1 }
            if succeeded && shred { self.noteShred(after: 0.15) }
            if !shred { self.lastLanding = Date.timeIntervalSinceReferenceDate }
            onLand()
            try? await Task.sleep(for: .seconds(paper.lifetime - paper.landTime))
            self.papers.removeAll { $0.id == paper.id }
            self.refreshShredder()
        }
    }

    /// The Trash was emptied: tip the basket over and pour everything out.
    func clearPile() {
        let now = Date.timeIntervalSinceReferenceDate
        poured = max(pileCount, 3)
        pileClearedAt = now
        Task {
            try? await Task.sleep(for: .seconds(0.22))
            SoundBoard.shared.play(.pour)
        }
        keepTicking(for: StageRenderer.pourDuration + 0.2)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(StageRenderer.pourDuration))
            self?.pileCount = 0
            self?.pileClearedAt = nil
        }
    }

    /// Keeps the pile in step with what is really in the Trash. It only shrinks when the Trash did
    /// (emptied or put back elsewhere); balls thrown just now stay until the next reading catches up.
    func syncPile(to count: Int, trashShrank: Bool) {
        guard pileClearedAt == nil else { return }
        if trashShrank || count > pileCount { pileCount = count }
    }

    /// Undo: balls jump back out of the basket and unfold on their way to `target`.
    func unthrow(icons: [NSImage?], to target: CGPoint) {
        let now = Date.timeIntervalSinceReferenceDate
        let mouth = basket.mouth
        for (i, icon) in icons.enumerated() {
            var rng = SeededRandom(nextSeed())
            let paper = ReturningPaper(born: now + Double(i) * 0.09,
                                       start: CGPoint(x: mouth.midX + rng.range(-16, 16), y: mouth.midY + 6),
                                       target: CGPoint(x: target.x + rng.range(-60, 60), y: target.y + rng.range(-30, 30)),
                                       seed: rng.next(), icon: icon)
            returning.append(paper)
        }
        pileCount = max(0, pileCount - icons.count)
        lastLanding = now
        SoundBoard.shared.play(.unfold)
        let total = ReturningPaper.duration + Double(icons.count) * 0.09
        keepTicking(for: total + 0.2)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(total + 0.1))
            self?.returning.removeAll { $0.born <= now + Double(icons.count) * 0.09 }
        }
    }

    /// Runs the frame clock only while something is moving.
    private func keepTicking(for duration: Double) {
        tickDeadline = max(tickDeadline, Date.timeIntervalSinceReferenceDate + duration)
        isTicking = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.05))
            guard let self, self.held == nil, Date.timeIntervalSinceReferenceDate >= self.tickDeadline else { return }
            self.isTicking = false
        }
    }
}

/// Transparent overlay that draws the basket and every paper in flight.
struct PaperStageView: View {
    let stage: PaperStage

    var body: some View {
        let snapshot = stage.snapshot
        TimelineView(.animation(minimumInterval: nil, paused: !stage.isTicking)) { timeline in
            Canvas { context, size in
                StageRenderer.draw(context, size: size, now: timeline.date.timeIntervalSinceReferenceDate, snapshot: snapshot)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { stage.canvasSize = $0 }
        .allowsHitTesting(false)
    }
}
