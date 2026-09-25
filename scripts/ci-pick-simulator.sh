#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator on the newest installed iOS runtime.
# Simulator names differ between CI images, so we pick one instead of hard-coding it.
set -euo pipefail

xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
best = None
for runtime, entries in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in entries:
        if device.get("isAvailable", True) and device["name"].startswith("iPhone"):
            if best is None or version > best[0]:
                best = (version, device["udid"], device["name"])
if best is None:
    sys.exit("No iPhone simulator is available")
print(best[1])
print("Using %s (iOS %d.%d)" % (best[2], best[0][0], best[0][1]), file=sys.stderr)
'
