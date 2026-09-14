# Menu-bar popover clipping — 1.7.1

The screenshot's cut-off header was reproduced in the real app. The popover occupied `(3076, 2563, 416, 686)` on a visible display at `(822, 1243, 3008, 1662)`: its top extended **344 points above** the visible display.

The original repro command was `python3 /private/tmp/quilt-popover-check/verify.py`, against temporary measurements from the actual menu-bar opening path. It failed with `panel header extends above the visible display`.

Setting `NSPopover.contentSize` alone did not fix the failure. Disabling `NSHostingController` automatic sizing and laying out the hosting view before presentation removed the large late resize/offset. The final controller also anchors the actual native window below the status item's own screen-space rectangle, with an inset from that display's visible edges. This includes native border and arrow dimensions.

The view fills the size assigned by AppKit. It no longer derives a fixed 660-point height from `NSScreen.main`. The library height is based on the number of rows, with scrolling for longer lists; switching to the picker explicitly resizes and reanchors the same panel. Concurrent open-pane controls are preserved and contribute to sizing.

## Verification

- `./scripts/test.sh`: 31 scenario groups / 39,680 assertions at the initial geometry pass, plus draft isolation, defaults persistence, and saved-setup preservation checks.
- Native regression uses the **production `MenuPopoverController`**, a real hosting view, and a menu-bar-sized anchor at the top of a real display. It opens, expands, shrinks, and reopens; all four actual window frames must fit the display.
- `python3 Tests/PopoverFixture/verify.py`: **PASS** for all four states. Actual frame heights: 404 → 686 → 404 → 404 points. Width: 416 points, including native chrome.
- Native dark-mode visual inspection confirmed the compact library, header, setup rows, and footer are present.
- Synthetic geometry checks include the user's vertically offset monitor, a negative-origin monitor, a 500-point-tall display, many saved setups, and anchors at both horizontal edges.
- Temporary production telemetry was removed. No window-arrangement or desktop-switching engine changes were required for this fix.

To repeat the native regression, build `./scripts/build-popover-check.sh`, open `.build/Quilt Popover Check.app`, click **Run native popover checks**, then run `python3 Tests/PopoverFixture/verify.py`. The fixture only manipulates its own test UI. Its report is written to `/private/tmp/quilt-popover-check/native-regression.json`.
