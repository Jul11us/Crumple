using Avalonia;
using Avalonia.Media;
using Crumple.Desktop.Ui;

namespace Crumple.Desktop.Art;

// A line-by-line port of the Mac version's PaperArt.swift: the sheet that crumples into a ball,
// the wire basket and the shredder. The numbers are the same, so the two versions look alike.

internal static class M
{
    public static double Clamp01(double x) => Math.Min(1, Math.Max(0, x));
    public static double EaseOutCubic(double x) => 1 - Math.Pow(1 - x, 3);
    public static double EaseInOutCubic(double x) => x < 0.5 ? 4 * x * x * x : 1 - Math.Pow(-2 * x + 2, 3) / 2;
    public static double Lerp(double a, double b, double t) => a + (b - a) * t;
    public static double Now => Environment.TickCount64 / 1000.0;
}

/// Deterministic noise, so a given paper crumples the same way on every frame (same generator as the Mac version).
internal struct SeededRandom(ulong seed)
{
    private ulong state = seed;

    public ulong Next()
    {
        unchecked
        {
            state += 0x9E3779B97F4A7C15;
            var z = state;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EB;
            return z ^ (z >> 31);
        }
    }

    public double Unit() => (Next() >> 11) / (double)(1UL << 53);
    public double Range(double a, double b) => a + (b - a) * Unit();
}

internal enum PaperPhase { Crumpling, Flying, Sinking, Bouncing, Loose, Shredding }

internal record struct PaperPose(Point Center, double Rotation, double Scale, double Crumple, double SheetScale,
    double Opacity, PaperPhase Phase);

internal static class PaperArt
{
    public static readonly Size Sheet = new(46, 58);
    public const double FoldSize = 11;
    public const double BallRadius = 14;

    private static readonly Point[] FineOutline = SheetOutline(34);
    private static readonly Point[] CoarseOutline = SheetOutline(20);

    private static Point[] SheetOutline(int count)
    {
        double w = Sheet.Width, h = Sheet.Height, f = FoldSize;
        return Resample([new(-w / 2, -h / 2), new(w / 2 - f, -h / 2), new(w / 2, -h / 2 + f), new(w / 2, h / 2), new(-w / 2, h / 2)], count);
    }

    private static Point[] Resample(Point[] polygon, int count)
    {
        var edges = polygon.Select((p, i) => (p, polygon[(i + 1) % polygon.Length])).ToArray();
        var lengths = edges.Select(e => Math.Sqrt(Math.Pow(e.Item2.X - e.p.X, 2) + Math.Pow(e.Item2.Y - e.p.Y, 2))).ToArray();
        var total = lengths.Sum();
        var points = new List<Point>();
        for (var e = 0; e < edges.Length; e++)
        {
            var steps = Math.Max(1, (int)Math.Round(count * lengths[e] / total));
            for (var j = 0; j < steps; j++)
            {
                var t = (double)j / steps;
                points.Add(new(M.Lerp(edges[e].p.X, edges[e].Item2.X, t), M.Lerp(edges[e].p.Y, edges[e].Item2.Y, t)));
            }
        }
        return points.ToArray();
    }

    public static StreamGeometry Polygon(IReadOnlyList<Point> points, bool close = true)
    {
        var geometry = new StreamGeometry();
        using var g = geometry.Open();
        g.BeginFigure(points[0], close);
        for (var i = 1; i < points.Count; i++) g.LineTo(points[i]);
        g.EndFigure(close);
        return geometry;
    }

    private static readonly Geometry FileGlyph = Geometry.Parse(IconData.File);

    public static void Draw(DrawingContext context, PaperPose pose, ulong seed, Color? tint = null, bool shadow = true,
        bool coarse = false, double lineScale = 1, double lumpiness = 1, bool face = true)
    {
        if (pose.Opacity <= 0.001) return;
        using var _o = context.PushOpacity(pose.Opacity);
        var transform = Matrix.CreateScale(pose.Scale, pose.Scale) * Matrix.CreateRotation(pose.Rotation)
            * Matrix.CreateTranslation(pose.Center.X, pose.Center.Y);
        using var _t = context.PushTransform(transform);

        var c = pose.Crumple;
        var s = pose.SheetScale;
        var w = Sheet.Width * s;
        var h = Sheet.Height * s;
        var wrinkle = Math.Sin(Math.PI * c);

        // Morph the flat sheet into a lumpy ball.
        var shapeRng = new SeededRandom(seed);
        var phase1 = shapeRng.Range(0, 2 * Math.PI);
        var phase2 = shapeRng.Range(0, 2 * Math.PI);
        var outline = coarse ? CoarseOutline : FineOutline;
        var points = new Point[outline.Length];
        for (var i = 0; i < outline.Length; i++)
        {
            var p = new Point(outline[i].X * s, outline[i].Y * s);
            var angle = Math.Atan2(p.Y, p.X);
            var lumps = 0.11 * Math.Sin(3 * angle + phase1) + 0.07 * Math.Sin(5 * angle + phase2);
            var r = BallRadius * (1 + (lumps + shapeRng.Range(-0.08, 0.08)) * lumpiness);
            var jitterX = shapeRng.Range(-1, 1) * 5 * s * wrinkle;
            var jitterY = shapeRng.Range(-1, 1) * 5 * s * wrinkle;
            points[i] = new(M.Lerp(p.X, Math.Cos(angle) * r, c) + jitterX, M.Lerp(p.Y, Math.Sin(angle) * r, c) + jitterY);
        }
        var path = Polygon(points);

        // Light always comes from the top-left of the screen, whatever the ball's spin.
        var lightAngle = -0.75 * Math.PI - pose.Rotation;
        var light = new Point(Math.Cos(lightAngle), Math.Sin(lightAngle));

        if (shadow)
        {
            var back = -pose.Rotation;
            var dx = (1.2 * Math.Cos(back) - 2.6 * Math.Sin(back)) / pose.Scale;
            var dy = (1.2 * Math.Sin(back) + 2.6 * Math.Cos(back)) / pose.Scale;
            // A soft shadow from a few spread copies (Avalonia has no blur filter for drawing).
            var alpha = 0.16 + 0.08 * c;
            foreach (var (spread, share) in new[] { (2.2, 0.35), (1.1, 0.35), (0.0, 0.45) })
            {
                var k = 1 + spread / BallRadius;
                using (context.PushTransform(Matrix.CreateScale(k, k) * Matrix.CreateTranslation(dx, dy)))
                    context.DrawGeometry(new SolidColorBrush(Color.FromArgb((byte)(255 * alpha * share), 0, 0, 0)), null, path);
            }
        }

        var reach = M.Lerp(Math.Max(w, h) / 2, BallRadius, c);
        context.DrawGeometry(new LinearGradientBrush
        {
            StartPoint = new RelativePoint(light.X * reach, light.Y * reach, RelativeUnit.Absolute),
            EndPoint = new RelativePoint(-light.X * reach, -light.Y * reach, RelativeUnit.Absolute),
            GradientStops = { new GradientStop(Colors.White, 0), new GradientStop(Gray(0.86), 1) },
        }, null, path);

        if (c > 0.02) DrawFacets(context, points, seed, c, lightAngle, lineScale);

        // The flat page: a file glyph, a few lines of "text", and a folded corner. Fades as it crumples.
        var faceAlpha = Math.Max(0, 1 - c / 0.4);
        if (face && faceAlpha > 0)
        {
            using var _fo = context.PushOpacity(faceAlpha);
            using var _fs = context.PushTransform(Matrix.CreateScale(1 - c * 0.6, 1 - c * 0.6));
            var side = 20 * s;
            using (context.PushTransform(Matrix.CreateScale(side / 24, side / 24) * Matrix.CreateTranslation(-side / 2, -h / 2 + 8 * s)))
                context.DrawGeometry(null, new Pen(new SolidColorBrush(Gray(0.6)), 1.6, lineCap: PenLineCap.Round, lineJoin: PenLineJoin.Round), FileGlyph);
            double[] fractions = [0.86, 0.68, 0.78];
            var linePen = new Pen(new SolidColorBrush(Gray(0.78)), 2.2 * s, lineCap: PenLineCap.Round);
            for (var i = 0; i < fractions.Length; i++)
            {
                var y = -h / 2 + (36 + i * 6.5) * s;
                var x0 = -w / 2 + 7 * s;
                context.DrawLine(linePen, new Point(x0, y), new Point(x0 + (w - 14 * s) * fractions[i], y));
            }
            var f = FoldSize * s;
            var ear = Polygon([new(w / 2 - f, -h / 2), new(w / 2 - f, -h / 2 + f), new(w / 2, -h / 2 + f)]);
            context.DrawGeometry(new LinearGradientBrush
            {
                StartPoint = new RelativePoint(w / 2 - f, -h / 2 + f, RelativeUnit.Absolute),
                EndPoint = new RelativePoint(w / 2 - f / 2, -h / 2 + f / 2, RelativeUnit.Absolute),
                GradientStops = { new GradientStop(Gray(0.8), 0), new GradientStop(Gray(0.95), 1) },
            }, new Pen(new SolidColorBrush(Gray(0.62)), 0.7), ear);
        }

        context.DrawGeometry(null, new Pen(new SolidColorBrush(Gray(0.45, 0.55)), 0.8 * lineScale, lineJoin: PenLineJoin.Round), path);
        if (tint is { } t) context.DrawGeometry(new SolidColorBrush(t, 0.28), null, path);
    }

    public static Color Gray(double white, double alpha = 1) =>
        Color.FromArgb((byte)(alpha * 255), (byte)(white * 255), (byte)(white * 255), (byte)(white * 255));

    /// Low-poly shading and crease lines that make the ball read as crumpled paper.
    private static void DrawFacets(DrawingContext g, Point[] points, ulong seed, double c, double lightAngle, double lineScale)
    {
        var rng = new SeededRandom(unchecked(seed + 0x51ED));
        const int ring = 6;
        var inner = new Point[ring];
        for (var i = 0; i < ring; i++)
        {
            var a = (double)i / ring * 2 * Math.PI + rng.Range(-0.4, 0.4);
            var r = BallRadius * rng.Range(0.25, 0.55);
            inner[i] = new(Math.Cos(a) * r, Math.Sin(a) * r);
        }
        var core = new Point(rng.Range(-2, 2), rng.Range(-2, 2));

        void Shade(Point a, Point b, Point d, double angle, double noise)
        {
            var lit = Math.Cos(angle - lightAngle);
            var dark = (0.5 - 0.5 * lit) * 0.9 + noise;
            var triangle = Polygon([a, b, d]);
            if (dark > 0.45)
                g.DrawGeometry(new SolidColorBrush(Color.FromArgb((byte)(255 * Math.Min(0.2, (dark - 0.45) * 0.35) * c), 0, 0, 0)), null, triangle);
            else
                g.DrawGeometry(new SolidColorBrush(Color.FromArgb((byte)(255 * Math.Min(0.55, (0.45 - dark) * 0.7) * c), 255, 255, 255)), null, triangle);
        }

        var creases = new List<(Point, Point)>();
        for (var i = 0; i < points.Length; i++)
        {
            var a = points[i];
            var b = points[(i + 1) % points.Length];
            var angle = Math.Atan2((a.Y + b.Y) / 2, (a.X + b.X) / 2);
            if (angle < 0) angle += 2 * Math.PI;
            var k = (int)(angle / (2 * Math.PI) * ring + 0.5) % ring;
            Shade(inner[k], a, b, angle, rng.Range(-0.35, 0.35));
            if (i % 3 == 0) creases.Add((inner[k], a));
        }
        for (var i = 0; i < ring; i++)
        {
            var a = inner[i];
            var b = inner[(i + 1) % ring];
            Shade(core, a, b, Math.Atan2((a.Y + b.Y) / 2, (a.X + b.X) / 2), rng.Range(-0.45, 0.45));
            creases.Add((a, b));
        }
        var pen = new Pen(new SolidColorBrush(Gray(0.4, 0.3 * c)), 0.6 * lineScale, lineCap: PenLineCap.Round);
        foreach (var (a, b) in creases) g.DrawLine(pen, a, b);
    }
}

// MARK: - Basket

internal readonly record struct BasketGeometry(Rect Rect)
{
    public static readonly Size Size = new(108, 104);
    public const double TrailingInset = 26;
    public const double BottomInset = 20;
    /// Space the bottom bar leaves free for the basket.
    public static double ReservedTrailing => TrailingInset + Size.Width + 18;
    /// Space a page leaves at its bottom so its last rows can scroll clear of the basket.
    public static double Clearance => BottomInset + Size.Height + 16;

    public static Rect RectIn(Size canvas) => new(canvas.Width - TrailingInset - Size.Width,
        canvas.Height - BottomInset - Size.Height, Size.Width, Size.Height);

    public double Scale => Rect.Width / Size.Width;
    public Rect Mouth => new(Rect.X, Rect.Y, Rect.Width, Rect.Width * 0.3);
    public Rect Base
    {
        get
        {
            var w = Rect.Width * 0.7;
            var h = w * 0.3;
            return new(Rect.Center.X - w / 2, Rect.Bottom - h, w, h);
        }
    }

    /// An ellipse between the mouth (t = 0) and the base (t = 1).
    public Rect Ring(double t) => new(M.Lerp(Mouth.X, Base.X, t), M.Lerp(Mouth.Y, Base.Y, t),
        M.Lerp(Mouth.Width, Base.Width, t), M.Lerp(Mouth.Height, Base.Height, t));

    public static Point PointOn(Rect r, double a) => new(r.Center.X + r.Width / 2 * Math.Cos(a), r.Center.Y + r.Height / 2 * Math.Sin(a));

    public static List<Point> Arc(Rect r, double a0, double a1, int steps = 28)
    {
        var points = new List<Point>(steps + 1);
        for (var i = 0; i <= steps; i++) points.Add(PointOn(r, a0 + (a1 - a0) * i / steps));
        return points;
    }

    /// The whole basket outline seen from the front.
    public StreamGeometry Silhouette => PaperArt.Polygon([.. Arc(Mouth, Math.PI, 2 * Math.PI), .. Arc(Base, 0, Math.PI)]);
    /// The front wall, between the front half of the rim and the front half of the base.
    public StreamGeometry FrontWall => PaperArt.Polygon([.. Arc(Mouth, 0, Math.PI), .. Arc(Base, Math.PI, 0)]);

    /// Whether a point is inside the silhouette (used to catch a ball let go right inside the basket).
    public bool Contains(Point p) => Silhouette.FillContains(p);
}

internal readonly record struct BasketStyle(Color Rim, Color Slat, Color Wall, Color Interior, double Shadow)
{
    public static BasketStyle App => new(Ink.C(Ink.Palette.BasketRim), Ink.C(Ink.Palette.BasketSlat),
        Ink.C(Ink.Palette.BasketWall), Ink.C(Ink.Palette.BasketInside), 0.14);
}

internal static class BasketArt
{
    public const int Slats = 10;

    private static IBrush Brush(Color c, double opacity = 1) => new SolidColorBrush(c, opacity);
    private static Pen Pen(Color c, double width, double opacity = 1) =>
        new(Brush(c, opacity), width, lineCap: PenLineCap.Round, lineJoin: PenLineJoin.Round);

    private static void Stroke(DrawingContext g, List<Point> points, Pen pen) => g.DrawGeometry(null, pen, PaperArt.Polygon(points, false));

    public static void DrawBack(DrawingContext g, BasketGeometry b, BasketStyle style)
    {
        var k = b.Scale;
        // The floor shadow: a soft ellipse under the base.
        var floor = b.Base.Inflate(new Thickness(10 * k, 0)).Translate(new Vector(0, b.Base.Height * 0.35));
        g.DrawEllipse(new RadialGradientBrush
        {
            GradientStops = { new GradientStop(Color.FromArgb((byte)(255 * style.Shadow * 1.4), 0, 0, 0), 0.3), new GradientStop(Colors.Transparent, 1) },
        }, null, floor.Inflate(new Thickness(5 * k, 4 * k)));
        g.DrawGeometry(Brush(style.Wall, 0.14), null, b.Silhouette);
        g.DrawEllipse(new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0.5, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(0.5, 1, RelativeUnit.Relative),
            GradientStops = { new GradientStop(Color.FromArgb((byte)(255 * 0.78), style.Interior.R, style.Interior.G, style.Interior.B), 0),
                new GradientStop(Color.FromArgb((byte)(255 * 0.42), style.Interior.R, style.Interior.G, style.Interior.B), 1) },
        }, null, b.Mouth);
        var back = Pen(style.Slat, 1.4 * k, 0.35);
        for (var i = 0; i < Slats; i++)
        {
            var a = Math.PI + Math.PI * (i + 0.5) / Slats;
            g.DrawLine(back, BasketGeometry.PointOn(b.Mouth, a), BasketGeometry.PointOn(b.Base, a));
        }
        Stroke(g, BasketGeometry.Arc(b.Mouth, Math.PI, 2 * Math.PI), Pen(style.Rim, 3.5 * k, 0.9));
    }

    public static void DrawFront(DrawingContext g, BasketGeometry b, BasketStyle style)
    {
        var k = b.Scale;
        Color W(double o) => Color.FromArgb((byte)(255 * o), style.Wall.R, style.Wall.G, style.Wall.B);
        g.DrawGeometry(new LinearGradientBrush
        {
            StartPoint = new RelativePoint(b.Rect.X, b.Rect.Center.Y, RelativeUnit.Absolute),
            EndPoint = new RelativePoint(b.Rect.Right, b.Rect.Center.Y, RelativeUnit.Absolute),
            GradientStops = { new GradientStop(W(0.32), 0), new GradientStop(W(0.16), 0.5), new GradientStop(W(0.28), 1) },
        }, null, b.FrontWall);
        foreach (var t in new[] { 0.36, 0.7 }) Stroke(g, BasketGeometry.Arc(b.Ring(t), 0, Math.PI), Pen(style.Slat, 1.5 * k));
        var front = Pen(style.Slat, 1.8 * k);
        for (var i = 0; i <= Slats; i++)
        {
            var a = Math.PI * i / Slats;
            g.DrawLine(front, BasketGeometry.PointOn(b.Mouth, a), BasketGeometry.PointOn(b.Base, a));
        }
        Stroke(g, BasketGeometry.Arc(b.Base, 0, Math.PI), Pen(style.Rim, 3 * k));
        Stroke(g, BasketGeometry.Arc(b.Mouth, 0, Math.PI), Pen(style.Rim, 4.5 * k));
        Stroke(g, BasketGeometry.Arc(b.Mouth.Translate(new Vector(0, -1.2 * k)), 0.18 * Math.PI, 0.62 * Math.PI), Pen(Colors.White, 1.2 * k, 0.45));
    }

    /// Paper balls already in the basket. It fills quickly at first, then more slowly.
    public static void DrawPile(DrawingContext g, BasketGeometry b, int count, double opacity)
    {
        if (count <= 0 || opacity <= 0) return;
        var r = 10.5 * b.Scale;
        var slots = PileSlots(b, r);
        int shown;
        if (count <= 8) shown = Math.Min(count, slots.Count);
        else
        {
            var extra = (slots.Count - 8) * (1 - Math.Exp(-(count - 8) / 40.0));
            shown = Math.Min(slots.Count, 8 + (int)extra);
        }
        for (var i = 0; i < shown; i++)
        {
            var rng = new SeededRandom(unchecked((ulong)i * 7919 + 17));
            var pose = new PaperPose(slots[i], rng.Range(0, 2 * Math.PI), r / PaperArt.BallRadius, 1, 1, opacity, PaperPhase.Sinking);
            PaperArt.Draw(g, pose, rng.Next(), shadow: false, coarse: true, face: false);
        }
    }

    private static List<Point> PileSlots(BasketGeometry b, double r)
    {
        var rng = new SeededRandom(77);
        var slots = new List<Point>();
        var y = b.Base.Center.Y - r * 0.55;
        while (y >= b.Mouth.Center.Y + r * 0.2)
        {
            var t = (y - b.Mouth.Center.Y) / (b.Base.Center.Y - b.Mouth.Center.Y);
            var width = M.Lerp(b.Mouth.Width, b.Base.Width, t) * 0.78;
            var n = Math.Max(1, (int)(width / (r * 1.75)));
            var spacing = width / n;
            var middle = (n - 1) / 2.0;
            foreach (var j in Enumerable.Range(0, n).OrderBy(j => Math.Abs(j - middle)))
            {
                var x = b.Rect.Center.X - width / 2 + spacing * (j + 0.5) + rng.Range(-2, 2) * b.Scale;
                slots.Add(new(x, y + rng.Range(-1.5, 1.5) * b.Scale));
            }
            y -= r * 1.3;
        }
        return slots;
    }
}
