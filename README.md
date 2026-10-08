# Tilez

**Window management made easy.** Tilez is a free, open-source window manager for macOS that you drive from the keyboard.

Press **Control–Option–Space** and your screen becomes a grid of its windows. Split, merge, resize, and swap them, pick a layout that fits, then press Return and everything moves into place.

- **Layouts that fit your windows.** Tilez shows every good way to arrange the windows you have, and **⌃⌥G** cycles through them from anywhere.
- **Workspaces.** Save the windows on a screen and bring the same ones back later, from wherever they went.
- **Screens that remember.** Unplug a monitor and plug it back in, and your windows go back where they were.
- **One key away.** Tile, realign, enlarge, swap, and undo without opening anything.
- **Stays on your Mac.** No accounts, no analytics, no network. It only needs Accessibility access to move your windows.

Website: [yisroelarnson.github.io/Tilez](https://yisroelarnson.github.io/Tilez/)

## Download

**[Download Tilez for Mac](https://github.com/YisroelArnson/Tilez/releases/latest/download/Tilez.dmg)** (macOS 14 or later)

Open the disk image and drag Tilez to Applications. The app is notarized by Apple and keeps itself up to date: it checks every 15 minutes and downloads new versions in the background. When one is ready, a blue dot appears on the menu bar icon and the grid shows **Restart to update**. One click installs it.

## Get started

1. Open Tilez. It lives in the menu bar as a small three-pane icon.
2. Allow **Accessibility** access when it asks, in System Settings → Privacy & Security → Accessibility. That's the only permission it needs.
3. Press **Control–Option–Space** to open the grid on the screen you're using.
4. Press **?** to see every shortcut, or use the dock at the bottom of the grid.
5. Press **Return** to apply your changes, or **Escape** to close without moving anything.

## The keys to know

| Keys | What they do |
| --- | --- |
| **⌃⌥ Space** | Open the grid |
| **⌃⌥ G** | Move the screen's windows into the next layout |
| **⌃⌥ T** | Tile every window on the screen |
| **⌃⌥ R** | Realign windows that have drifted out of line |
| **⌃⌥ W** | Browse your workspaces; **⌃⌥ 1–9** opens one |
| **⌃⌥ S** | Save the workspace on this screen |
| **⌃⌥ Z** | Undo the last arrangement |
| **⌃⌥ Return** | Enlarge a window, and put it back |
| **⌃⌥ N** | Quick Add an app as a new tile |
| **?** | Every other shortcut, inside the grid |

## Learn more

- **[The Tilez guide](GUIDE.md)** walks through every control, option, and ability.
- **[Developing Tilez](DEVELOPMENT.md)** covers building from source, testing, and releasing.

## Build from source

```bash
xcode-select --install
git clone https://github.com/YisroelArnson/Tilez.git
cd Tilez
bash scripts/update.sh
```

The script builds Tilez, installs it in `/Applications`, and launches it. Run it again from the folder to update. Details are in [DEVELOPMENT.md](DEVELOPMENT.md).

*Tilez was formerly Window Quilt.*
