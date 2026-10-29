#!/usr/bin/env python3
"""Summarize monitor/oref-engine-timing.json exported from the test phone.
Durations include data loading, profile/cache work and persistence, not only CPU.
"""
import argparse
import json
import math
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('timings')
args = parser.parse_args()
rows = json.load(open(args.timings))
for engine in ['javascript', 'swift']:
    values = sorted(float(r['duration']) * 1000 for r in rows if r['engine'] == engine)
    if not values:
        print(f'{engine}: no samples')
        continue
    assert all(math.isfinite(v) and v >= 0 for v in values)
    p95 = values[max(0, math.ceil(len(values) * 0.95) - 1)]
    print(f'{engine}: n={len(values)}, median={statistics.median(values):.1f} ms, p95={p95:.1f} ms')
