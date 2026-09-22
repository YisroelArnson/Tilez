import Foundation

/// Bounded, lazy menu traversal so window creation does not scan an entire app.
public enum WindowMenuCommand {
    public static func find<Node>(in root: Node, title: (Node) -> String,
                                  isItem: (Node) -> Bool, isEnabled: (Node) -> Bool,
                                  children: (Node) -> [Node], isDefault: (Node) -> Bool) -> Node? {
        let labels = ["new window", "new finder window", "new chat window", "new chatgpt window",
                      "new codex window", "new task window", "new main window"]
        var remaining = 500
        func search(_ node: Node, depth: Int, inWindowMenu: Bool = false) -> (Node, Bool)? {
            guard depth < 10, remaining > 0 else { return nil }
            remaining -= 1
            guard isEnabled(node) else { return nil }
            let name = title(node).replacingOccurrences(of: "…", with: "")
                .replacingOccurrences(of: "...", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matches = isItem(node) && (labels.contains(name)
                || name.hasPrefix("new window with profile") || name.hasPrefix("new window ("))
            let descendants = children(node)
            if isItem(node), descendants.isEmpty {
                // Cmd-N is meaningful only inside a known New Window submenu.
                // Elsewhere it may create a document or replace the current chat.
                if inWindowMenu && isDefault(node) { return (node, true) }
                return matches ? (node, false) : nil
            }
            let within = inWindowMenu || matches
            var fallback: (Node, Bool)?
            for child in descendants {
                if let match = search(child, depth: depth + 1, inWindowMenu: within) {
                    if !within || match.1 { return match }
                    if fallback == nil { fallback = match }
                }
            }
            // A submenu heading can accept AXPress without creating any window.
            // Return an actionable descendant, or report the command unavailable.
            return fallback
        }
        return search(root, depth: 0)?.0
    }
}
