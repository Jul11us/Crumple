using Avalonia;
using Avalonia.Media;
using Crumple.Desktop.Ui;

namespace Crumple.Desktop.Art;

/// The shredder that appears above the basket: a dark head with a slot on top, over a wire bin.
/// What goes in here is deleted for good, so it only shows up when asked for.
internal readonly record struct ShredderGeometry(Rect Rect)
{
    public static readonly Size Size = new(92, 96);
    public const double Gap = 26;

    public static Rect RectAbove(BasketGeometry basket) => new(basket.Rect.Center.X - Size.Width / 2,
        basket.Rect.Y - Gap - Size.Height, Size.Width, Size.Height);

    public Rect Head => new(Rect.X, Rect.Y, Rect.Width, Rect.Height * 0.34);
    public Rect Bin => new(Rect.X + 7, Head.Bottom - 2, Rect.Width - 14, Rect.Bottom - Head.Bottom + 2);
    /// The opening along the top edge of the head.
    public Rect Slot => new(Head.X + 14, Head.Y - 2, Head.Width - 28, 5);
    /// Where a throw has to come down to be caught by the slot.
    public Rect CatchZone => Slot.Inflate(6);
}

internal static class ShredderArt
{
    public static void Draw(DrawingContext g, ShredderGeometry s, int strips, double? shreddingSince, double now)
    {
        var ink = Ink.Primary;
        g.DrawRectangle(Ink.Raised, null, s.Bin, 4, 4);
        var bars = new Pen(Ink.Fill(0.18), 1);
        for (var i = 1; i < 7; i++)
        {
            var x = s.Bin.X + s.Bin.Width * i / 7;
            g.DrawLine(bars, new Point(x, s.Bin.Y + 4), new Point(x, s.Bin.Bottom - 3));
        }

        // Strips already in the bin, then the ones falling out of the head right now.
        var rng = new SeededRandom(91);
        const double stripWidth = 4;
        var edge = new Pen(new SolidColorBrush(Color.FromArgb(89, 0, 0, 0)), 0.7);
        for (var i = 0; i < Math.Min(strips, 18); i++)
        {
            var x = s.Bin.X + 6 + i % 9 * (s.Bin.Width - 12) / 9 + rng.Range(-1, 1);
            var h = rng.Range(18, 34);
            var y = s.Bin.Bottom - 4 - h - i / 9 * 6;
            g.DrawRectangle(Brushes.White, edge, new Rect(x, y, stripWidth, h), 1, 1);
        }
        var running = shreddingSince is { } since && now - since < 0.9;
        if (running)
        {
            var k = M.Clamp01((now - shreddingSince!.Value) / 0.9);
            for (var i = 0; i < 7; i++)
            {
                var x = s.Slot.X + i * (s.Slot.Width - stripWidth) / 6;
                g.DrawRectangle(new SolidColorBrush(Colors.White, 1 - k * 0.3), edge, new Rect(x, s.Head.Bottom - 2, stripWidth, 10 + 30 * k), 1, 1);
            }
        }
        g.DrawRectangle(null, new Pen(ink, 2), s.Bin, 4, 4);

        // The head, with the slot along its top and a small light that is on while it runs.
        g.DrawRectangle(ink, null, s.Head, 7, 7);
        g.DrawRectangle(Ink.B(Ink.Palette.Base, 0.85), null, s.Slot, 2.5, 2.5);
        g.DrawEllipse(running ? Ink.Danger : Ink.B(Ink.Palette.Base, 0.35), null, new Rect(s.Head.Right - 14, s.Head.Center.Y + 2, 5, 5));
        var grill = new Pen(Ink.B(Ink.Palette.Base, 0.3), 1.2);
        for (var i = 0; i < 3; i++)
        {
            var y = s.Head.Center.Y + 1 + i * 4;
            g.DrawLine(grill, new Point(s.Head.X + 12, y), new Point(s.Head.X + 34, y));
        }
    }
}

internal static class StageRenderer
{
    public const double PourDuration = 1.5;

    /// How far the basket leans over while it is emptied: over, a pause while it pours, back up.
    public static double TipAngle(double t)
    {
        if (t < 0.32) return -1.2 * M.EaseInOutCubic(t / 0.32);
        if (t < 0.9) return -1.2;
        return -1.2 * (1 - M.EaseInOutCubic(M.Clamp01((t - 0.9) / 0.45)));
    }

    private static Matrix About(Point pivot, Matrix m) =>
        Matrix.CreateTranslation(-pivot.X, -pivot.Y) * m * Matrix.CreateTranslation(pivot.X, pivot.Y);

    private static void Glow(DrawingContext g, Rect rect, Color color, double strength)
    {
        if (strength <= 0) return;
        g.DrawEllipse(new RadialGradientBrush
        {
            GradientStops = { new GradientStop(Color.FromArgb((byte)(255 * strength), color.R, color.G, color.B), 0.35), new GradientStop(Colors.Transparent, 1) },
        }, null, rect);
    }

    public static void Draw(DrawingContext context, Size size, double now, PaperStage stage, bool showBasket)
    {
        var basket = new BasketGeometry(BasketGeometry.RectIn(size));
        var pourT = stage.PileClearedAt is { } cleared ? now - cleared : (double?)null;

        // The basket wobbles and squashes a little each time something lands.
        var basketMatrix = Matrix.Identity;
        var sinceLanding = now - stage.LastLanding;
        if (sinceLanding is >= 0 and < 1.6)
        {
            var angle = 0.075 * Math.Exp(-sinceLanding * 5.5) * Math.Sin(sinceLanding * 24);
            var squash = 0.06 * Math.Exp(-sinceLanding * 11) * Math.Cos(sinceLanding * 30);
            basketMatrix = About(new Point(basket.Rect.Center.X, basket.Rect.Bottom),
                Matrix.CreateScale(1 + squash * 0.6, 1 - squash) * Matrix.CreateRotation(angle));
        }
        // Emptying the bin: the basket tips over to the left about its bottom-left corner.
        if (pourT is { } pt)
            basketMatrix = basketMatrix * About(new Point(basket.Base.X, basket.Rect.Bottom), Matrix.CreateRotation(TipAngle(pt)));

        // The shredder slides down into place above the basket when it's wanted, and back up after.
        var shredder = new ShredderGeometry(ShredderGeometry.RectAbove(basket));
        var shown = 0.0;
        if (stage.ShredderShownAt is { } shownAt)
        {
            shown = M.EaseOutCubic(M.Clamp01((now - shownAt) / 0.25));
            if (stage.ShredderHiddenAt is { } hidden && now > hidden) shown *= 1 - M.EaseInOutCubic(M.Clamp01((now - hidden) / 0.25));
        }
        if (showBasket && shown > 0.01)
        {
            using (context.PushOpacity(shown))
            using (context.PushTransform(Matrix.CreateTranslation(0, -16 * (1 - shown))))
            {
                if (stage.Held is { ArmedAt: not null } armed)
                {
                    var distance = Math.Sqrt(Math.Pow(armed.Location.X - shredder.Slot.Center.X, 2) + Math.Pow(armed.Location.Y - shredder.Slot.Center.Y, 2));
                    Glow(context, shredder.Slot.Inflate(new Thickness(16, 14)), Ink.C(Ink.Palette.Danger), Math.Max(0, 1 - distance / 220) * 0.5);
                }
                ShredderArt.Draw(context, shredder, stage.StripCount, stage.LastShred, now);
            }
        }

        // The rim glows when a paper in hand gets close: ink to aim, red if it won't go in.
        if (showBasket && stage.Held is { ArmedAt: null } held)
        {
            var distance = Math.Sqrt(Math.Pow(held.Location.X - basket.Mouth.Center.X, 2) + Math.Pow(held.Location.Y - basket.Mouth.Center.Y, 2));
            using (context.PushTransform(basketMatrix))
                Glow(context, basket.Mouth.Inflate(new Thickness(18, 14)), held.Blocked ? Colors.Red : Ink.C(Ink.Palette.Accent),
                    Math.Max(0, 1 - distance / 220) * 0.6);
        }

        var inFront = new List<(PaperPose Pose, ulong Seed, Color? Tint)>();
        void Place(PaperPose pose, ulong seed)
        {
            switch (pose.Phase)
            {
                case PaperPhase.Shredding:
                    // A sheet going into the shredder disappears below the slot.
                    using (context.PushClip(new Rect(0, 0, size.Width, shredder.Slot.Center.Y)))
                        PaperArt.Draw(context, pose, seed);
                    break;
                case PaperPhase.Sinking:
                    using (context.PushTransform(basketMatrix))
                    using (context.PushGeometryClip(basket.Silhouette))
                    using (context.PushTransform(basketMatrix.Invert()))
                        PaperArt.Draw(context, pose, seed, face: false);
                    break;
                case PaperPhase.Bouncing: inFront.Add((pose, seed, Colors.Red)); break;
                case PaperPhase.Loose: inFront.Add((pose, seed, null)); break;
                default: PaperArt.Draw(context, pose, seed); break;
            }
        }

        if (showBasket)
        {
            using (context.PushTransform(basketMatrix))
            {
                BasketArt.DrawBack(context, basket, BasketStyle.App);
                BasketArt.DrawPile(context, basket, stage.PileCount, pourT is { } p && p >= 0.3 ? 0 : 1);
            }
        }
        foreach (var paper in stage.Papers)
        {
            var elapsed = now - paper.Born;
            if (elapsed >= 0 && elapsed <= paper.Lifetime) Place(paper.Pose(elapsed), paper.Seed);
        }
        foreach (var toss in stage.Tossed)
        {
            var elapsed = now - toss.Born;
            if (elapsed >= 0 && elapsed <= toss.Lifetime) Place(toss.Pose(elapsed), toss.Seed);
        }
        if (showBasket)
            using (context.PushTransform(basketMatrix))
                BasketArt.DrawFront(context, basket, BasketStyle.App);

        // The balls tumbling out of the tipped basket and off the bottom of the window.
        if (pourT is { } t && t > 0.24)
        {
            var pivot = new Point(basket.Base.X, basket.Rect.Bottom);
            var a = TipAngle(0.32);
            var mouth = basket.Mouth.Center;
            double dx = mouth.X - pivot.X, dy = mouth.Y - pivot.Y;
            var lip = new Point(pivot.X + dx * Math.Cos(a) - dy * Math.Sin(a), pivot.Y + dx * Math.Sin(a) + dy * Math.Cos(a));
            for (var i = 0; i < Math.Min(stage.Poured, 14); i++)
            {
                var rng = new SeededRandom(unchecked((ulong)i * 2654435761 + 5));
                var s = t - 0.24 - i * 0.035;
                if (s <= 0) continue;
                var v = new Vector(-rng.Range(120, 300), -rng.Range(40, 200));
                var center = new Point(lip.X + rng.Range(-10, 10) + v.X * s, lip.Y + rng.Range(-6, 6) + v.Y * s + 0.5 * TossedPaper.Gravity * s * s);
                if (center.Y >= size.Height + 30) continue;
                PaperArt.Draw(context, new PaperPose(center, rng.Range(0, 6) + s * 8, 0.72, 1, 1, 1, PaperPhase.Loose), rng.Next(), face: false);
            }
        }
        foreach (var paper in stage.Returning)
        {
            var elapsed = now - paper.Born;
            if (elapsed >= 0 && elapsed <= ReturningPaper.Duration) PaperArt.Draw(context, paper.Pose(elapsed), paper.Seed);
        }
        foreach (var (pose, seed, tint) in inFront) PaperArt.Draw(context, pose, seed, tint);
        if (stage.Held is { } inHand) PaperArt.Draw(context, inHand.Pose(now), inHand.Seed);
    }
}
