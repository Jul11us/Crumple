using Avalonia;
using Avalonia.Threading;

namespace Crumple.Desktop.Art;

// A port of the Mac version's PaperMotion.swift: how a sheet pops out of its row, crumples,
// flies in an arc and lands in (or bounces off) the basket, and how a ball thrown by hand travels.

/// Timeline of one file during a batch clean: pops out of its row, gets crumpled, is thrown in an arc,
/// then either sinks into the basket or (if it couldn't be moved) bounces off the rim.
internal sealed class Paper
{
    public const double LiftDuration = 0.18, CrumpleStart = 0.12, CrumpleEnd = 0.52, SinkDuration = 0.28,
        BounceDuration = 0.85, LiftHeight = 30, ShredDuration = 0.5;

    public Guid Id { get; } = Guid.NewGuid();
    public double Born { get; }
    public Point Origin { get; }
    public Point Target { get; }
    public double Flight { get; }
    public ulong Seed { get; }
    public bool Succeeded { get; }
    public bool Shred { get; }
    private readonly double spin, tilt, bounceDirection;

    public double LandTime => CrumpleEnd + Flight;
    public double Lifetime => LandTime + (Succeeded ? (Shred ? ShredDuration : SinkDuration) : BounceDuration);

    public Paper(double born, Point origin, BasketGeometry basket, bool succeeded, ulong seed, ShredderGeometry? shredder = null)
    {
        var rng = new SeededRandom(seed);
        var mouth = shredder?.Slot ?? basket.Mouth;
        Shred = shredder != null;
        var fromLeft = origin.X < mouth.Center.X;
        Target = succeeded
            ? new Point(mouth.Center.X + mouth.Width * rng.Range(-0.18, 0.18), mouth.Center.Y + 1)
            : new Point(fromLeft ? mouth.X + 4 : mouth.Right - 4, mouth.Center.Y - 3);
        var start = new Point(origin.X, origin.Y - LiftHeight);
        var distance = Math.Sqrt(Math.Pow(Target.X - start.X, 2) + Math.Pow(Target.Y - start.Y, 2));
        Born = born;
        Origin = origin;
        Seed = seed;
        Succeeded = succeeded;
        Flight = 0.55 + Math.Min(0.4, distance / 2200);
        spin = (rng.Unit() < 0.5 ? -1 : 1) * rng.Range(2.5, 4.5) * Math.PI;
        tilt = rng.Range(-0.16, 0.16);
        bounceDirection = fromLeft ? -1 : 1;
    }

    public PaperPose Pose(double elapsed)
    {
        var lift = M.EaseOutCubic(M.Clamp01(elapsed / LiftDuration));
        var crumple = Shred ? 0 : M.EaseInOutCubic(M.Clamp01((elapsed - CrumpleStart) / (CrumpleEnd - CrumpleStart)));

        // 1. Pop out of the row and get crumpled (or, for the shredder, stay a flat sheet), with a little wind-up.
        if (elapsed < CrumpleEnd)
        {
            var windT = M.Clamp01((elapsed - 0.38) / (CrumpleEnd - 0.38));
            var wind = Math.Sin(windT * Math.PI) * 8;
            var direction = Target.X >= Origin.X ? 1 : -1;
            var shake = Math.Sin(elapsed * 46) * 0.16 * Math.Sin(Math.PI * crumple);
            return new(new Point(Origin.X - direction * wind, Origin.Y - LiftHeight * lift + wind * 0.5),
                tilt * lift + shake, 1, crumple, 0.55 + 0.45 * lift, 1, PaperPhase.Crumpling);
        }

        // 2. Fly along a parabola into the basket.
        var t = elapsed - CrumpleEnd;
        if (t < Flight)
        {
            var u = t / Flight;
            var p0 = new Point(Origin.X, Origin.Y - LiftHeight);
            var p2 = Target;
            var peakY = Math.Max(30, Math.Min(p0.Y, p2.Y) - Math.Max(70, Math.Abs(p2.X - p0.X) * 0.28));
            var control = new Point((p0.X + p2.X) / 2, 2 * peakY - (p0.Y + p2.Y) / 2);
            var inv = 1 - u;
            var x = inv * inv * p0.X + 2 * inv * u * control.X + u * u * p2.X;
            var y = inv * inv * p0.Y + 2 * inv * u * control.Y + u * u * p2.Y;
            return new(new Point(x, y), Shred ? tilt * (1 - u) : tilt + spin * u, 1 - 0.22 * u, Shred ? 0 : 1, 1, 1, PaperPhase.Flying);
        }

        // 3a. Sink into the basket, or get pulled down into the shredder…
        var d = t - Flight;
        if (Succeeded && Shred)
        {
            var k = M.EaseInOutCubic(M.Clamp01(d / ShredDuration));
            return new(new Point(Target.X, Target.Y + 44 * k), 0, 0.78, 0, 1, 1, PaperPhase.Shredding);
        }
        if (Succeeded)
        {
            var k = M.Clamp01(d / SinkDuration);
            return new(new Point(Target.X, Target.Y + 30 * k * k), tilt + spin + 0.6 * k, 0.78, 1, 1, 1 - k, PaperPhase.Sinking);
        }

        // 3b. …or bounce off the rim and fall away.
        var position = new Point(Target.X + bounceDirection * 150 * d, Target.Y - 230 * d + 750 * d * d);
        return new(position, tilt + spin - 7 * d * bounceDirection, 0.78, 1, 1, 1 - M.Clamp01((d - 0.35) / 0.45), PaperPhase.Bouncing);
    }
}

/// A sheet the user is dragging. It crumples in their hand while they line up the throw.
internal sealed class HeldPaper
{
    public required string ItemId { get; init; }
    public required double GrabbedAt { get; init; }
    public required Point Origin { get; init; }
    public Point Location { get; set; }
    public required ulong Seed { get; init; }
    /// This file can't be cleaned right now; the rim glows red as a warning.
    public bool Blocked { get; init; }
    /// When the shredder key went down: the sheet in hand smooths back out flat.
    public double? ArmedAt { get; set; }

    public double Crumple(double now)
    {
        var c = M.EaseInOutCubic(M.Clamp01((now - GrabbedAt - 0.04) / 0.32));
        return ArmedAt is { } armed ? c * (1 - M.EaseOutCubic(M.Clamp01((now - armed) / 0.18))) : c;
    }

    public PaperPose Pose(double now)
    {
        var elapsed = now - GrabbedAt;
        var follow = M.EaseOutCubic(M.Clamp01(elapsed / 0.14));
        var grow = M.EaseOutCubic(M.Clamp01(elapsed / 0.18));
        var c = Crumple(now);
        var shake = Math.Sin(elapsed * 46) * 0.16 * Math.Sin(Math.PI * c);
        return new(new Point(M.Lerp(Origin.X, Location.X, follow), M.Lerp(Origin.Y, Location.Y, follow)),
            shake, 1, c, 0.55 + 0.45 * grow, 1, PaperPhase.Loose);
    }
}

internal enum TossKind { Make, Rim, Miss, Shred }

/// A paper ball the user let go of. Its whole path is worked out at release:
/// straight in, off the rim, or a miss that falls out of the window.
internal sealed class TossedPaper
{
    public const double Gravity = 2200;

    public Guid Id { get; } = Guid.NewGuid();
    public string ItemId { get; }
    public double Born { get; }
    public Point Start { get; }
    public Vector Velocity { get; }
    public ulong Seed { get; }
    public double StartCrumple { get; }
    public TossKind Kind { get; }
    public double ImpactTime { get; }
    public Point ImpactPoint { get; }
    private readonly double direction;
    private readonly Vector rebound;
    public double Lifetime { get; set; }
    /// Whether cleaning worked; null until the file operation finishes.
    public bool? Succeeded { get; set; }
    /// For the shredder: when the user confirmed or cancelled (the sheet waits in the slot until then).
    public double? ResolvedAt { get; set; }

    public TossedPaper(string itemId, double born, Point start, Vector velocity, ulong seed, double startCrumple,
        BasketGeometry basket, Size canvas, ShredderGeometry? shredder = null)
    {
        const double g = Gravity;
        var mouth = basket.Mouth;
        var kind = TossKind.Miss;
        var impactTime = 0.0;
        var impactPoint = start;
        var dir = velocity.X >= 0 ? -1.0 : 1.0;

        // With the shredder out, a sheet that comes down onto its slot is caught there.
        if (shredder is { } s)
        {
            var zone = s.CatchZone;
            if (zone.Contains(start))
            {
                kind = TossKind.Shred;
                impactPoint = new Point(start.X, s.Slot.Center.Y);
            }
            else
            {
                var disc = velocity.Y * velocity.Y + 2 * g * (zone.Center.Y - start.Y);
                var t = disc >= 0 ? (-velocity.Y + Math.Sqrt(disc)) / g : -1;
                var x = start.X + velocity.X * Math.Max(0, t);
                if (t > 0 && x >= zone.X && x <= zone.Right)
                {
                    kind = TossKind.Shred;
                    impactTime = t;
                    impactPoint = new Point(Math.Min(Math.Max(x, s.Slot.X + 8), s.Slot.Right - 8), s.Slot.Center.Y);
                }
            }
        }

        if (kind == TossKind.Shred) { }
        else if (start.Y > mouth.Center.Y && basket.Contains(start)) kind = TossKind.Make; // let go right inside the basket
        else
        {
            // When does the ball come back down through the rim's height?
            var disc = velocity.Y * velocity.Y + 2 * g * (mouth.Center.Y - start.Y);
            var t = disc >= 0 ? (-velocity.Y + Math.Sqrt(disc)) / g : -1;
            if (t > 0)
            {
                var x = start.X + velocity.X * t;
                var offset = x - mouth.Center.X;
                if (Math.Abs(offset) <= mouth.Width / 2 - 4)
                {
                    kind = TossKind.Make;
                    impactPoint = new Point(x, mouth.Center.Y + 1);
                }
                else if (Math.Abs(offset) <= mouth.Width / 2 + 10)
                {
                    kind = TossKind.Rim;
                    dir = offset < 0 ? -1 : 1;
                    impactPoint = new Point(x, mouth.Center.Y - 3);
                }
                if (kind != TossKind.Miss) impactTime = t;
            }
        }

        var impactVY = velocity.Y + g * impactTime;
        rebound = new Vector(dir * (Math.Abs(velocity.X) * 0.35 + 90), -Math.Abs(impactVY) * 0.35 - 120);

        double ExitTime(Point p, Vector v)
        {
            var t = (-v.Y + Math.Sqrt(Math.Max(0, v.Y * v.Y + 2 * g * (canvas.Height + 40 - p.Y)))) / g;
            if (v.X > 1) t = Math.Min(t, (canvas.Width + 40 - p.X) / v.X);
            if (v.X < -1) t = Math.Min(t, (p.X + 40) / -v.X);
            return Math.Min(3, Math.Max(0.2, t));
        }

        ItemId = itemId;
        Born = born;
        Start = start;
        Velocity = velocity;
        Seed = seed;
        StartCrumple = startCrumple;
        Kind = kind;
        ImpactTime = impactTime;
        ImpactPoint = impactPoint;
        direction = dir;
        Lifetime = kind switch
        {
            TossKind.Make => impactTime + Paper.BounceDuration,
            TossKind.Rim => impactTime + ExitTime(impactPoint, rebound),
            TossKind.Miss => ExitTime(start, velocity),
            _ => 600, // waits in the slot until the user confirms; see PaperStage.ResolveShred
        };
    }

    public PaperPose Pose(double t)
    {
        const double g = Gravity;
        var crumple = Kind == TossKind.Shred ? StartCrumple : Math.Min(1, StartCrumple + t / 0.18);
        var spin = Math.Max(-14, Math.Min(14, Velocity.X * 0.006));
        var fade = 1 - M.Clamp01((t - (Lifetime - 0.3)) / 0.3);
        static Point Ballistic(Point p, Vector v, double s) => new(p.X + v.X * s, p.Y + v.Y * s + 0.5 * g * s * s);

        if (Kind == TossKind.Miss || t < ImpactTime)
            return new(Ballistic(Start, Velocity, t), spin * t, 1 - 0.2 * M.Clamp01(t / 0.5), crumple, 1,
                Kind == TossKind.Miss ? fade : 1, Kind == TossKind.Miss ? PaperPhase.Loose : PaperPhase.Flying);

        var d = t - ImpactTime;
        var spun = spin * ImpactTime;
        if (Kind == TossKind.Shred)
        {
            var waited = (ResolvedAt ?? Born + t) - Born - ImpactTime;
            var r = Math.Max(0, d - waited);
            switch (Succeeded)
            {
                case true:
                    var k = M.EaseInOutCubic(M.Clamp01(r / Paper.ShredDuration));
                    return new(new Point(ImpactPoint.X, ImpactPoint.Y - 10 + 54 * k), 0, 0.8, 0, 1, 1, PaperPhase.Shredding);
                case false:
                    return new(new Point(ImpactPoint.X - 120 * r, ImpactPoint.Y - 12 - 380 * r + 900 * r * r), -3 * r, 0.8, crumple, 1,
                        1 - M.Clamp01((r - 0.5) / 0.4), PaperPhase.Loose);
                default:
                    // Held in the jaws, quivering, while the confirmation is up.
                    var jiggle = Math.Sin(t * 38) * 1.2;
                    return new(new Point(ImpactPoint.X + jiggle, ImpactPoint.Y - 10), jiggle * 0.01, 0.8, crumple, 1, 1, PaperPhase.Shredding);
            }
        }
        if (Kind == TossKind.Rim)
            return new(Ballistic(ImpactPoint, rebound, d), spun - 6 * d * direction, 0.8, 1, 1, fade, PaperPhase.Loose);
        if (Succeeded == false)
            return new(new Point(ImpactPoint.X + direction * 150 * d, ImpactPoint.Y - 230 * d + 750 * d * d), spun - 7 * d * direction,
                0.78, 1, 1, 1 - M.Clamp01((d - 0.35) / 0.45), PaperPhase.Bouncing);
        var sink = Math.Min(1, d / Paper.SinkDuration);
        return new(new Point(ImpactPoint.X, ImpactPoint.Y + 30 * sink * sink), spun + 0.6 * sink, 0.78, 1, 1, 1 - sink, PaperPhase.Sinking);
    }
}

/// A paper ball that jumps back out of the basket and smooths itself flat on the way, for undo.
internal sealed class ReturningPaper(double born, Point start, Point target, ulong seed)
{
    public const double Duration = 1.0;
    public double Born { get; } = born;
    public ulong Seed { get; } = seed;

    public PaperPose Pose(double t)
    {
        const double pop = 0.14, land = 0.78;
        if (t < pop)
        {
            var k = M.EaseOutCubic(t / pop);
            return new(new Point(start.X, start.Y - 34 * k), 0.4 * k, 0.8, 1, 1, 1, PaperPhase.Loose);
        }
        var p0 = new Point(start.X, start.Y - 34);
        if (t < land)
        {
            var u = (t - pop) / (land - pop);
            var peakY = Math.Min(p0.Y, target.Y) - Math.Max(60, Math.Abs(target.X - p0.X) * 0.22);
            var control = new Point((p0.X + target.X) / 2, 2 * peakY - (p0.Y + target.Y) / 2);
            var inv = 1 - u;
            var center = new Point(inv * inv * p0.X + 2 * inv * u * control.X + u * u * target.X,
                inv * inv * p0.Y + 2 * inv * u * control.Y + u * u * target.Y);
            var unfold = M.EaseInOutCubic(u);
            return new(center, 0.4 + 2.2 * u * (1 - u), 0.8 + 0.3 * unfold, 1 - unfold, 1, 1, PaperPhase.Loose);
        }
        var f = M.Clamp01((t - land) / (Duration - land));
        return new(new Point(target.X, target.Y - 6 * f), 0, 1.1, 0, 1, 1 - f, PaperPhase.Loose);
    }
}

/// Everything on the paper stage: papers in flight, the one in hand, the pile in the basket, the shredder.
internal sealed class PaperStage
{
    public List<Paper> Papers { get; } = [];
    public List<TossedPaper> Tossed { get; } = [];
    public HeldPaper? Held { get; private set; }
    public int PileCount { get; private set; }
    public double LastLanding { get; private set; } = -100;
    public double? PileClearedAt { get; private set; }
    public double? ShredderShownAt { get; private set; }
    public double? ShredderHiddenAt { get; private set; }
    public int StripCount { get; private set; }
    public double? LastShred { get; private set; }
    public List<ReturningPaper> Returning { get; } = [];
    /// How many balls were in the basket when it was tipped out.
    public int Poured { get; private set; }

    public Size CanvasSize { get; set; } = new(1080, 720);
    private ulong seed = 0x5EED;
    private double tickDeadline;

    /// Asks the view for frames until this time.
    public event Action? NeedsFrames;
    public bool IsTicking => Held != null || M.Now < tickDeadline;

    private BasketGeometry Basket => new(BasketGeometry.RectIn(CanvasSize));
    private ShredderGeometry Shredder => new(ShredderGeometry.RectAbove(Basket));

    private static void After(double seconds, Action action) =>
        DispatcherTimer.RunOnce(action, TimeSpan.FromSeconds(Math.Max(0.001, seconds)));

    private ulong NextSeed()
    {
        unchecked { seed = seed * 6364136223846793005 + 1442695040888963407; }
        return seed;
    }

    private void KeepTicking(double duration)
    {
        tickDeadline = Math.Max(tickDeadline, M.Now + duration);
        NeedsFrames?.Invoke();
    }

    // The shredder

    /// The shredder key held while dragging: bring the shredder out and flatten the sheet.
    public void SetArmed(bool armed)
    {
        if (Held is not { Blocked: false } paper || armed == (paper.ArmedAt != null)) return;
        paper.ArmedAt = armed ? M.Now : null;
        RefreshShredder();
    }

    /// The user confirmed (shredded) or cancelled a sheet waiting in the slot.
    public void ResolveShred(Guid id, bool shredded)
    {
        if (Tossed.FirstOrDefault(x => x.Id == id) is not { } toss) return;
        var now = M.Now;
        toss.Succeeded = shredded;
        toss.ResolvedAt = now;
        toss.Lifetime = now - toss.Born + (shredded ? Paper.ShredDuration + 0.1 : 1.0);
        KeepTicking(2.5);
        if (shredded) NoteShred(0.2);
        Sounds.Play(shredded ? Sound.Shred : Sound.Clank, shredded ? 1 : 0.5);
        After(shredded ? Paper.ShredDuration + 0.1 : 1.0, () => { Tossed.Remove(toss); RefreshShredder(); });
    }

    private void NoteShred(double delay) => After(delay, () => { StripCount++; LastShred = M.Now; });

    /// Out while it is armed or anything is headed for it; tucked away a moment after the last sheet.
    private void RefreshShredder()
    {
        var now = M.Now;
        var wanted = Held?.ArmedAt != null || Papers.Any(x => x.Shred) || Tossed.Any(x => x.Kind == TossKind.Shred);
        if (wanted)
        {
            ShredderShownAt ??= now;
            ShredderHiddenAt = null;
            KeepTicking(0.4);
        }
        else if (ShredderShownAt != null && ShredderHiddenAt == null)
        {
            var hideAt = now + 0.9;
            ShredderHiddenAt = hideAt;
            KeepTicking(1.3);
            After(1.2, () =>
            {
                if (ShredderHiddenAt != hideAt) return;
                ShredderShownAt = null;
                ShredderHiddenAt = null;
            });
        }
    }

    // Throwing by hand

    public void Grab(string itemId, Point origin, Point location, bool blocked)
    {
        Held = new HeldPaper { ItemId = itemId, GrabbedAt = M.Now, Origin = origin, Location = location, Seed = NextSeed(), Blocked = blocked };
        KeepTicking(0.5);
        Sounds.Play(Sound.Crumple, 0.7);
    }

    public void MoveHeld(Point location)
    {
        if (Held != null) { Held.Location = location; NeedsFrames?.Invoke(); }
    }

    /// Lets go. `landed` runs at impact with whether it went in (not for the shredder, which waits).
    public TossedPaper? Release(Vector velocity, Action<TossedPaper>? landed = null)
    {
        if (Held is not { } held) return null;
        var now = M.Now;
        var speed = velocity.Length;
        if (speed > 3200) velocity *= 3200 / speed;
        var toss = new TossedPaper(held.ItemId, now, held.Pose(now).Center, velocity, held.Seed, held.Crumple(now),
            Basket, CanvasSize, held.ArmedAt != null ? Shredder : null);
        Held = null;
        Tossed.Add(toss);
        RefreshShredder();
        if (toss.Kind == TossKind.Shred) { KeepTicking(600); return toss; }
        KeepTicking(toss.Lifetime + 1.7);
        if (toss.Kind != TossKind.Miss)
            After(toss.ImpactTime, () =>
            {
                var cleaned = toss.Succeeded != false;
                if (toss.Kind == TossKind.Make && cleaned) PileCount++;
                LastLanding = M.Now;
                Sounds.Play(toss.Kind == TossKind.Make && cleaned ? Sound.Swish : Sound.Clank);
                landed?.Invoke(toss);
            });
        After(toss.Lifetime, () => Tossed.Remove(toss));
        return toss;
    }

    public void Settle(Guid id, bool succeeded)
    {
        if (Tossed.FirstOrDefault(x => x.Id == id) is { } toss) toss.Succeeded = succeeded;
    }

    // Automatic cleaning

    /// `shred`: the file is deleted for good, so the sheet goes into the shredder instead of the basket.
    public void Launch(Point origin, bool succeeded, Action onLand, bool shred = false)
    {
        var paper = new Paper(M.Now, origin, Basket, succeeded, NextSeed(), shred ? Shredder : null);
        Papers.Add(paper);
        RefreshShredder();
        KeepTicking(paper.Lifetime + 1.7);
        After(Paper.CrumpleStart, () => { if (!shred) Sounds.Play(Sound.Crumple, 0.4); });
        After(paper.LandTime, () =>
        {
            Sounds.Play(!succeeded ? Sound.Clank : shred ? Sound.Shred : Sound.Swish, 0.7);
            if (succeeded && !shred) PileCount++;
            if (succeeded && shred) NoteShred(0.15);
            if (!shred) LastLanding = M.Now;
            onLand();
        });
        After(paper.Lifetime, () => { Papers.Remove(paper); RefreshShredder(); });
    }

    /// The bin was emptied: tip the basket over and pour everything out.
    public void ClearPile()
    {
        Poured = Math.Max(PileCount, 3);
        PileClearedAt = M.Now;
        After(0.22, () => Sounds.Play(Sound.Pour));
        KeepTicking(StageRenderer.PourDuration + 0.2);
        After(StageRenderer.PourDuration, () => { PileCount = 0; PileClearedAt = null; });
    }

    /// Keeps the pile in step with what is really in the bin. It only shrinks when the bin did;
    /// balls thrown just now stay until the next reading catches up.
    public void SyncPile(int count, bool binShrank)
    {
        if (PileClearedAt != null) return;
        if (binShrank || count > PileCount) PileCount = count;
        NeedsFrames?.Invoke();
    }

    /// Undo: balls jump back out of the basket and unfold on their way to `target`.
    public void Unthrow(int count, Point target)
    {
        var now = M.Now;
        var mouth = Basket.Mouth;
        for (var i = 0; i < count; i++)
        {
            var rng = new SeededRandom(NextSeed());
            Returning.Add(new ReturningPaper(now + i * 0.09,
                new Point(mouth.Center.X + rng.Range(-16, 16), mouth.Center.Y + 6),
                new Point(target.X + rng.Range(-60, 60), target.Y + rng.Range(-30, 30)), rng.Next()));
        }
        PileCount = Math.Max(0, PileCount - count);
        LastLanding = now;
        Sounds.Play(Sound.Unfold);
        var total = ReturningPaper.Duration + count * 0.09;
        KeepTicking(total + 0.2);
        After(total + 0.1, () => Returning.RemoveAll(x => x.Born <= now + count * 0.09));
    }
}
