#!/usr/bin/env python3
"""Validate frame/count reports produced by the native active-layout fixture run."""
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '/private/tmp/quilt-active-fixture')
def read(name):
    return json.loads((root / name).read_text())
def named(windows, predicate):
    return {w['title']: w for w in windows if predicate(int(w['title'].split()[-1]))}

before = read('before-b-shrink.json')
after = read('after-b-shrink.json')
assert len(after) == len(before) - 2, 'Shrink did not close exactly two windows'
assert len(named(after, lambda n: n >= 9)) == 6, 'Target set did not retain six'
assert named(before, lambda n: n <= 8) == named(after, lambda n: n <= 8), 'Shrink changed another set'
closed = read('after-b-close.json')
assert named(closed, lambda n: True) == named(after, lambda n: n <= 8), 'Closing the set affected another set'
before = read('before-grow.json')
after = read('after-grow.json')
assert len(before) == 4 and len(after) == 6, 'Growth did not create two windows'
assert named(before, lambda n: n in (3, 4)) == named(after, lambda n: n in (3, 4)), 'Growth changed a neighboring set'
assert {w['title'] for w in after} - {w['title'] for w in before} == {'Quilt test window 5', 'Quilt test window 6'}, 'Growth borrowed an existing window'
print('PASS: shrink, close-set, and growth isolation; other-set identities and frames unchanged.')
