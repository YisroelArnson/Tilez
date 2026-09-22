import TilezCore

func checkWindowMenus() {
    struct Item {
        var title: String
        var enabled = true
        var isItem = true
        var defaultShortcut = false
        var children: [Item] = []
    }
    func find(_ item: Item) -> String? {
        WindowMenuCommand.find(in: item, title: { $0.title }, isItem: { $0.isItem },
            isEnabled: { $0.enabled }, children: { $0.children }, isDefault: { $0.defaultShortcut })?.title
    }
    let terminal = Item(title: "New Window", children: [Item(title: "", isItem: false, children: [
        Item(title: "Other profile"), Item(title: "Basic", defaultShortcut: true)
    ])])
    assert(find(terminal) == "Basic", "New Window must resolve to its default profile action, not the submenu heading")
    assert(find(Item(title: "New Window")) == "New Window")
    assert(find(Item(title: "New Finder Window…")) == "New Finder Window…")
    assert(find(Item(title: "New Window (Default Profile)")) == "New Window (Default Profile)")
    assert(find(Item(title: "New Window with Profile – Basic")) == "New Window with Profile – Basic")
    assert(find(Item(title: "New Window", children: [Item(title: "", isItem: false)])) == nil,
           "An unpopulated submenu must not be pressed as a window command")
    assert(find(Item(title: "New Window", enabled: false, children: [Item(title: "Basic", defaultShortcut: true)])) == nil)
    assert(find(Item(title: "New Window", children: [Item(title: "Basic", enabled: false, defaultShortcut: true)])) == nil)
    assert(find(Item(title: "New Tab", children: [Item(title: "Basic", defaultShortcut: true)])) == nil)
    assert(find(Item(title: "New Chat", defaultShortcut: true)) == nil)
    assert(find(Item(title: "New Document", defaultShortcut: true)) == nil)
    let shell = Item(title: "Shell", children: [Item(title: "", isItem: false, children: [
        Item(title: "New Tab"), terminal
    ])])
    assert(find(Item(title: "", isItem: false, children: [shell])) == "Basic")
    var visited = 0
    let huge = Item(title: "", isItem: false, children: Array(repeating: Item(title: "Unrelated"), count: 1000))
    let result = WindowMenuCommand.find(in: huge, title: { visited += 1; return $0.title },
        isItem: { $0.isItem }, isEnabled: { $0.enabled }, children: { $0.children }, isDefault: { $0.defaultShortcut })
    assert(result == nil && visited <= 500, "Menu search must stay bounded")
    print("PASS: direct and profile-submenu window commands, disabled menus, tab/chat exclusion, bounded traversal")
}
