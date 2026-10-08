# Tilez guide

Everything Tilez can do, and the keys that do it. New to Tilez? Start with the [README](README.md). Inside the grid, press **?** for a list of every shortcut.

- [The grid](#the-grid)
- [Workspaces](#workspaces)
- [Put windows back when a screen reconnects](#put-windows-back-when-a-screen-reconnects)
- [Quick add a tile](#quick-add-a-tile)
- [Tile or cycle layouts without the grid](#tile-or-cycle-layouts-without-the-grid)
- [Realign windows](#realign-windows)
- [Open another window of an app](#open-another-window-of-an-app)
- [Swap two windows by dragging](#swap-two-windows-by-dragging)
- [Enlarge a window temporarily](#enlarge-a-window-temporarily)
- [How Tilez treats your windows](#how-tilez-treats-your-windows)

## The grid

A native macOS pane editor for the screen and desktop you are using. The overlay starts from every window on the desktop, at its actual size and position, including uneven sizes, overlapping arrangements, and windows hidden behind others. An empty desktop starts with one empty pane.

Press **Control–Option–Space** or click the grid icon in the menu bar. The preview mirrors the current desktop. Opening it does not move, restore, or open any windows.

- Use a **+ on any pane edge** to split off a neighbor, then choose its app. **Drag any edge of a pane** to resize it, or **drag a corner** to resize in both directions. An edge shared with other panes moves them along with it, like dragging the divider between them; an edge at the screen border or facing empty space moves on its own and stops just short of the next pane. Dragging a corner where panes meet moves that whole junction. **Double-click** a divider to center it between its panes again. Next to each edge's **+**, a merge button grows that pane over its neighbors on that side when they line up, such as turning a column of stacked panes into one tall pane. The pane whose button you click keeps its app. Drag panes to swap them.
- **The dock** at the bottom holds the main actions, each labeled with its shortcut: **Layouts (G)**, **Add pane (K)**, **Tile all (T)**, **Workspaces (W)**, **Apply (↵)**, **Shortcuts (?)**, which lists every other command, and **…** for the rest. Narrow screens keep the icons and shortcuts and drop the labels.
- Click a pane to select it. **Double-click** it, or click its app icon, to search for an installed app and select it. Hovering a pane shows its edge controls, so you can split or merge without selecting it first. Mix apps or choose the same app more than once.
- **Drag a cell onto another to swap** their apps and existing window assignments. While you drag, the other pane slides into your pane's spot so you can see the result; move back to cancel. **Shift-drag to copy an app** into another pane, creating a separate window when the grid opens. Right-click a cell to repeat its app into every empty cell.
- **Return** applies the preview. New panes open independent windows on the desktop where you invoked Tilez. Existing windows on other desktops are not borrowed.
- **Remove pane / Delete** expands a neighboring pane where possible and closes the removed window on Apply. Undo restores the pane before applying; Escape cancels the draft. Native save dialogs remain under the app’s control.
- **⌘Shift–Delete** removes all panes from the current draft, leaving one empty cell. Press **Return** to close their windows, or **⌘Z** to restore the entire layout in one step. Also available under **… → Close all panes on Apply**.
- Invoke the same shortcut again to edit the current desktop's grid, then choose **Apply**.
- The keyboard shortcut targets the active app’s foremost window’s display; clicking the menu icon targets that menu bar’s display. Each desktop remembers the selected cell during the session.
- **Arrow keys** select neighboring cells without wrapping. **Shift–Arrow** moves or swaps the selected app and its exact window assignment. **⌘Shift–Arrow** copies the app into the neighboring cell and follows the copy. Copying onto a different app replaces it, and that pane's window closes on Apply; copying onto the same app just moves the selection, keeping its window. These edit the draft; **Return** applies it to your windows.
- **Option–Arrow** splits the selected pane toward that arrow (left, right, above, or below) and opens the app chooser for the new pane. Type an app name and press Return to assign it. **⌘Z** undoes the split after dismissing the chooser.
- **Letters are commands in the grid, no ⌘ needed:** **G** Layouts, **K** add a pane, **T** tile all, **W** workspaces, **R** realign, **S** save the workspace (**⇧S** a new one), **O** saved layouts, **N** a new empty grid. The ⌘ versions work too, and **⌘Z** undoes. **?** lists every shortcut.
- **Space** chooses an app for the selected pane, and **1–9** for that pane; a double-click works too. Type the app's name, use **↑/↓**, and **Return** assigns it; **Escape** goes back. **Delete** removes the selected pane.
- **Option–Shift–Arrow** merges the selected pane with the pane or panes beside it in that direction, when they line up into one rectangle. The selected pane keeps its app; absorbed windows close on Apply, and **⌘Z** undoes the merge.
- **T** tiles every pane in an even grid: in reading order, sized close to square for the screen's shape, with a short last row stretched to fill it. When windows overlap, including ones stacked exactly on top of each other, a pill at the bottom offers the same **Tile all**. **Control–Option–T** does it anywhere, without the grid (see below). **⌘Z** undoes it, and Apply moves the windows. Also under **… → Tile all**.
- **Bring windows from another screen** with **… → Bring N windows from *screen***. They join this screen's windows in an even grid, and Apply moves them here.
- **R** realigns panes that have drifted out of line, such as windows captured from the desktop. Edges within a few percent of each other snap onto one shared line with an even gap, panes near the screen edge reach it, and near-even splits settle on halves, thirds, or quarters. The arrangement stays the same, larger holes are kept, and **⌘Z** undoes it. Also available under **… → Realign panes**.
- **G** opens **Layouts** in the panes' place: ways to arrange exactly the windows on the screen, so none is left out. They're worked out from the window count: the even grid first, then a main window with the rest beside it (on either side), columns, a tall middle with stacked sides, two on top of the rest, a wide top, and the other grid shapes that fit, without lopsided layouts or panes too small to use. With no windows, it offers fixed presets for filling panes with apps. A custom grid of up to **6 columns × 4 rows** is always last. Each card shows where your windows would go, in reading order. Press **1–9** for a layout, or use the arrows and **Return**; **⇧ arrows** size the custom grid. **Escape** or **G** again closes it. The draft changes; Apply moves the windows.
- **K** uses an empty pane or splits the selected pane to make room. **⌘C / ⌘V** copies an app assignment into an empty cell, without sharing its live window binding.
- **⌘Z** undoes a grid edit, and **N** starts a new empty grid. The bar's **…** menu lists the grid's actions with their shortcuts, plus Undo last window arrangement, Keyboard Shortcuts, Check for Updates, and Quit.
- **O** opens a popup above the dock's **Workspaces** button for saving and for your workspaces and saved layouts. At the top: save the workspace this screen is showing, save a new workspace, or **Save as layout…**, which keeps the grid's apps as a reusable layout of app choices, not windows or a fixed screen or desktop. Below: your workspaces and layouts, each drawn as its arrangement. Type to filter, use ↑/↓, then Return; a search field appears once the list is long. A workspace brings back its windows; a layout loads a draft of apps on any desktop. **S** saves the shown workspace directly, or names a new one when the screen shows none (see Workspaces below); **⇧S** saves a new workspace.
- **?** shows every shortcut in one sheet, with or without Shift; any key closes it.
- **Escape** closes the app picker first, then the overlay. Clicking on another screen also closes it. While opening windows it stops the request; windows already created stay available.

## Workspaces

A **workspace** is a set of open windows kept in one arrangement, on one screen or several. A **saved layout** is its opposite: apps only, and opening it always opens new windows.

- **Open a workspace** from the **Workspaces** gallery: **W** in the grid, or **Control–Option–W** anywhere, shows every workspace as a large preview of its arrangement, with each window's app icon, in the panes' place. Click one, press its number, or use the arrows and **Return**. Its exact windows come back into their panes from wherever they are: minimized, on another desktop, or on another screen. A one-screen workspace comes to the screen you're on; a multi-screen workspace returns to each of its screens at once. Other windows already on those screens stay where they are.
- **Switch with Control–Option–1 through 9.** The number is the workspace's position in the gallery. **⌘← / ⌘→** move the highlighted workspace earlier or later, and right-click → **Move to position** puts it anywhere, renumbering the shortcuts. The pencil, or a double-click on the name, renames it in place; names are unique, since saving under an existing name replaces that workspace. The trash deletes it; its windows stay open.
- **The gallery's header** saves the workspace this screen shows (**S**) or a new one (**⇧S**). The workspace this screen shows is marked **On this screen**.
- **A workspace never opens a window.** When one of its windows closes, or its app quits, the window leaves the workspace for good and a neighboring pane grows into its space. When the last one closes, the workspace is gone.
- **Save** with **Control–Option–S** (or **S** in the grid). That saves the workspace the screen is showing. When it isn't showing one, you name a new one. **Control–Option–Shift–S** (or **⇧S** in the grid) always saves a new workspace; with more than one display, choose **This screen** or **All screens**. A new workspace with an existing name replaces it.
- **Rearranging, resizing, or swapping** windows marks the workspace as edited (a dot on the grid's workspaces button) until you save. Closing a window, or adding one with **Quick Add**, updates the workspace by itself. Quick Add's new window joins the workspace its screen is showing. A window can belong to several workspaces.
- A screen shows a workspace from when you open or save it on that screen's current desktop until you open a different workspace or a saved layout there. A screen also shows a workspace when most of that workspace's windows are on it, however they got there, so **S** updates it rather than making a new one.
- **New windows join the workspace the screen shows:** panes you add in the grid and Apply, windows brought from another screen, Quick Add, and ⌃⌥ right-click. Saving is only needed after rearranging.
- **When saving would make a new workspace** but some already share windows with the screen, the save form offers to update them first, best match first, such as **Update “Coding” · 4 of its 5 windows are here**. The ⌃⌥⇧S panel offers the best match the same way.
- Pulling windows off other desktops uses the same desktop bridge as the grid (macOS 26.4+). When a screen is showing a full-screen app, that screen switches to a regular desktop for the workspace and the app stays in full screen on its own desktop. The workspace's own full-screen windows leave full screen and join the layout.

## Put windows back when a screen reconnects

When a monitor disconnects, macOS moves its windows onto the screens that are left and often doesn't move them back. While more than one screen is connected, Tilez remembers which screen each window is on and where. When a screen comes back and windows that belonged to it are still on another screen, a prompt at the top of that screen offers **Put Back**. They return to their places on the screen's current desktop. Minimized windows, windows of hidden apps, and windows opened while the screen was away stay where they are.

- Check **Always put windows back** in the prompt, or choose **… → Put windows back when a screen reconnects → Automatically** in the grid, to skip the prompt.
- After **Not Now**, the grid on that screen shows a **Put back** pill for 15 minutes.
- Tilez waits a few seconds after a screen comes or goes, so windows macOS puts back by itself are left alone. The same goes for screens that disconnect while the Mac sleeps.

## Quick add a tile

Press **Control–Option–N** anywhere to open a search panel of your apps, with recently added apps at the top. Type to filter, use ↑/↓ to choose, and press Return (or click) to open the app as a new tile. Tilez fills an empty pane if the desktop has one; otherwise it splits the largest pane along its longer side and fits the new window there. Every other window stays where it is. Escape, or clicking elsewhere, closes the panel.

## Tile or cycle layouts without the grid

**Control–Option–T** tiles every window on the current screen and desktop in an even grid, like **T** in the grid. **Control–Option–G** moves them into the next layout that fits all of them, from the same choices as **Layouts**; press it again to keep cycling, and a pill names each layout. Windows glide into place, an enlarged window returns to its pane first, and **Control–Option–Z** puts everything back. With the grid open, both act on its draft instead.

**Control–Option–Z** undoes the last window arrangement from anywhere: a tile, a layout, a realign, an Apply from the grid, an opened workspace, or a Quick Add, one step at a time. A pill says what it undid. With the grid open, it undoes the draft's last edit, like **⌘Z**. Also under **… → Undo last window arrangement**.

## Realign windows

Press **Control–Option–R** anywhere to tidy the windows on the current screen and desktop without opening the grid. It works like **R** in the grid: edges that nearly line up snap onto shared lines with an even gap, windows near the screen edge reach it, and near-even splits settle on halves, thirds, or quarters. Windows glide into place and keep their arrangement; wider holes, minimized, hidden, and full-screen windows are left alone. An enlarged window on that screen returns to its pane first. **… → Undo last window arrangement** puts everything back. With the grid open, the shortcut realigns its panes instead.

## Open another window of an app

Hold **Control–Option** and right-click a window (a two-finger click on a trackpad) to open another window of that app beside it. The clicked window's pane splits along its longer side, the new window takes one half, and every other window stays where it is. When the screen is showing a workspace, the new window joins it. The app never sees the click, so no context menu opens. When macOS opens the new window as a tab, because the window already shows tabs or you prefer tabs, Tilez moves the tab into its own window with the app's **Move Tab to New Window** command, so it gets its own pane. Apps that can't open another window, or a pane too small to split, show why, the same as **Quick Add**.

## Swap two windows by dragging

Hold **Control–Option** and drag a window from anywhere inside it. The window follows the pointer; move it over another window and the two trade places live, gliding into position: the other window slides into your window's original spot and yours takes on its size. Release there to keep the swap. Release anywhere else, even after a small nudge, and the window returns exactly to where it started. A Control–Option click without dragging enlarges the window instead, and ordinary title-bar drags move windows as usual. Enlarged and full-screen windows never swap.

## Enlarge a window temporarily

Press **Control–Option–Return** in any window, or **Control–Option–click** it, to enlarge it over its neighbors, filling the screen with a 10-point margin. Nothing else moves. It stays enlarged while you click or switch to other windows. Each screen and desktop keeps its own enlarged window, so you can enlarge one window per monitor and per desktop without them affecting each other. Press the shortcut again on the same screen and desktop, or Control–Option–click the enlarged window, to return it to exactly where it was. Control–Option–clicking a different window puts back the one enlarged on that screen and desktop and enlarges the clicked one. Tilez consumes Control–Option–clicks so apps don't also treat them as right-clicks; ordinary clicks and Control-clicks are untouched. Opening the grid puts back only the enlarged window on the screen and desktop it opens on; quitting Tilez puts them all back. Only standard, resizable windows outside full screen can be enlarged; anything else beeps.

## How Tilez treats your windows

The invocation captures a particular display and desktop. Tilez reuses eligible windows there and opens independent windows for remaining cells. New windows can inherit an app's full-screen Space; Tilez identifies those new windows, waits for their transitions, restores them, and moves them back before applying the grid. Existing windows on unrelated desktops are not gathered. A window's identity includes its owning process launch, preventing stale IDs from matching after an app restart.

Each invocation takes a fresh WindowServer snapshot of the current desktop. Every window on the desktop becomes a pane at its actual bounds, front windows drawn above the ones behind them. A pane can also hold a window brought from another screen's current desktop; Apply moves it onto this screen and desktop. Accessibility refinement runs off the UI thread and never overwrites a draft once editing starts. Escape discards the draft. Only explicitly saved templates persist; they include unequal pane geometry but no live window identities. The editor does not run legacy all-app polling or auto-restore monitors.

A native macOS full-screen window appears as one pane. Applying it unchanged keeps it full screen. Applying edits first restores that exact window to its regular desktop on the same display, re-reads the usable display bounds, and opens any added panes there. The overlay explains this transition before Apply. Switching desktops while editing dismisses the overlay.

Apps must support independent windows to occupy multiple cells. Tilez uses their enabled New Window command, not New Chat or New Conversation actions that might replace existing content. If an app cannot create a window, is showing a dialog, or imposes a minimum size, the overlay reports the problem. AX bounds are checked after the app has time to settle, with bounded retries for only the windows that have not settled. Windows already in place finish immediately.

New Window submenus are resolved to an enabled action, preferring the default profile's Command-N item. This supports Terminal-style profile menus without pressing the submenu heading or choosing an arbitrary profile. Menu traversal remains bounded and runs on the Accessibility worker during grid application.
