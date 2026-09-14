"""Verify the fixture's real native-window bounds, not just its content size."""
import json
from pathlib import Path
report = json.loads(Path('/private/tmp/quilt-popover-check/native-regression.json').read_text())
assert report['passed'], report['error']
assert len(report['checks']) == 4, 'Not all open/expand/shrink/reopen checks ran'
assert report['checks'][0]['height'] < report['checks'][1]['height'], 'The library did not shrink to its content'
print('PASS: native popover opens, expands, shrinks, and reopens entirely inside its display')
