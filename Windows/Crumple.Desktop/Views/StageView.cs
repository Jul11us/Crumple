using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Crumple.Desktop.Art;
using Crumple.Desktop.Model;

namespace Crumple.Desktop.Views;

/// Transparent overlay that draws the basket and every paper in flight. It only asks for frames while something moves.
internal sealed class StageView : Control
{
    private readonly AppModel model;
    private bool frameRequested;

    public StageView(AppModel model)
    {
        this.model = model;
        IsHitTestVisible = false;
        model.Stage.NeedsFrames += RequestFrame;
    }

    private void RequestFrame()
    {
        if (frameRequested) return;
        frameRequested = true;
        if (TopLevel.GetTopLevel(this) is { } top)
            top.RequestAnimationFrame(_ => { frameRequested = false; InvalidateVisual(); if (model.Stage.IsTicking) RequestFrame(); });
        else { frameRequested = false; InvalidateVisual(); }
    }

    protected override void OnSizeChanged(SizeChangedEventArgs e)
    {
        base.OnSizeChanged(e);
        model.Stage.CanvasSize = e.NewSize;
    }

    public override void Render(DrawingContext context) =>
        StageRenderer.Draw(context, Bounds.Size, M.Now, model.Stage, model.ShowsBasket);
}
