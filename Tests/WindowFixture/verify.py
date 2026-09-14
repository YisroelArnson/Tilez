#!/usr/bin/env python3
"""Check the native fixture's own telemetry after running a setup through Quilt's UI."""
import argparse
import json
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument('report', type=Path)
p.add_argument('--count', type=int, default=3)
p.add_argument('--preserved', type=Path, help='Compare with a report captured before Keep full screen')
a = p.parse_args()
windows = json.loads(a.report.read_text())
assert len(windows) == a.count, f'Expected {a.count} windows, found {len(windows)}'
if a.preserved:
    before = json.loads(a.preserved.read_text())
    assert windows == before, 'Keep full screen changed a window or Space'
    assert all(w['fullScreen'] for w in windows), 'A window left full screen'
    print(f'PASS: {a.count} full-screen windows and their Spaces preserved unchanged')
else:
    assert all(not w['fullScreen'] and not w['minimized'] for w in windows), 'Windows not restored before tiling'
    assert all(w['spaces'] == windows[0]['spaces'] and w['spaces'] for w in windows), 'Windows on different desktops'
    for i, w in enumerate(windows):
        for other in windows[i + 1:]:
            overlap = min(w['x'] + w['w'], other['x'] + other['w']) - max(w['x'], other['x']) > 1 and min(w['y'] + w['h'], other['y'] + other['h']) - max(w['y'], other['y']) > 1
            assert not overlap, f'Windows {i + 1} and {windows.index(other) + 1} overlap'
    print(f'PASS: exactly {a.count} restored windows, one desktop, no overlaps')
