import Foundation

public enum MenuPanelGeometry {
    public static func contentSize(arranging: Bool, setupCount: Int, needsPermission: Bool, visibleFrame: CGRect, activeLayoutCount: Int = 0) -> CGSize {
        let preferredHeight = arranging ? 660.0 : 250.0 + Double(max(1, min(5, setupCount + activeLayoutCount))) * 64
            + (activeLayoutCount > 0 ? 44 : 0) + (needsPermission ? 48 : 0)
        // Reserve room for the native popover's border/arrow and a screen-edge inset.
        return CGSize(width: max(1, min(390, visibleFrame.width - 40)),
                      height: max(1, min(preferredHeight, visibleFrame.height - 40)))
    }

    public static func origin(panelSize: CGSize, anchor: CGRect, visibleFrame: CGRect) -> CGPoint {
        let safe = visibleFrame.insetBy(dx: 4, dy: 4)
        let x = max(safe.minX, min(anchor.midX - panelSize.width / 2, safe.maxX - panelSize.width))
        let top = min(anchor.minY, safe.maxY)
        let y = max(safe.minY, top - panelSize.height)
        return CGPoint(x: x, y: y)
    }
}
