import Foundation

/// Discovery and automatic arrangement are separate decisions.
public struct WindowAvailability {
    public var accessible: Bool
    public var hidden: Bool
    public var minimized: Bool
    public var fullScreen: Bool
    public var resizable: Bool
    public var document: Bool
    public init(hidden: Bool = false, minimized: Bool = false, fullScreen: Bool = false,
                resizable: Bool = true, document: Bool = true, accessible: Bool = true) {
        self.accessible = accessible
        self.hidden = hidden; self.minimized = minimized; self.fullScreen = fullScreen
        self.resizable = resizable; self.document = document
    }
    public var listed: Bool { document }
    public var automatic: Bool { listed && accessible && !hidden && !minimized && !fullScreen && resizable }
    public func needsFullScreenExit(preserve: Bool) -> Bool { fullScreen && !preserve }
}
