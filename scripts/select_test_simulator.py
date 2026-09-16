#!/usr/bin/env python3
"""Print the UDID of the best available iPhone simulator for running the tests.

Runner images decide which simulators exist, so CI resolves a destination at
run time rather than pinning a device name that may disappear with the next
image. Run it locally the same way: `python3 scripts/select_test_simulator.py`.
"""

import json
import re
import subprocess
import sys

MINIMUM_IOS_MAJOR = 17


def runtime_version(identifier):
    match = re.search(r"iOS-(\d+)-(\d+)", identifier)
    if match is None:
        return None
    return int(match.group(1)), int(match.group(2))


def device_rank(name):
    """Prefer a current, full-size iPhone.

    The UI tests tap controls close to the bottom of the screen, which is
    tightest on SE and mini, so those are chosen only as a last resort.
    """
    if re.fullmatch(r"iPhone \d+ Pro", name):
        return 3
    if re.fullmatch(r"iPhone \d+", name):
        return 2
    if "SE" in name or "mini" in name:
        return 0
    return 1


def main():
    listing = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        capture_output=True,
        text=True,
        check=True,
    )
    devices_by_runtime = json.loads(listing.stdout)["devices"]

    best = None
    for identifier, devices in devices_by_runtime.items():
        version = runtime_version(identifier)
        if version is None or version[0] < MINIMUM_IOS_MAJOR:
            continue
        for device in devices:
            if not device.get("isAvailable") or "iPhone" not in device["name"]:
                continue
            key = (version, device_rank(device["name"]), device["name"])
            if best is None or key > best[0]:
                best = (key, device)

    if best is None:
        sys.exit(
            f"No available iPhone simulator running iOS {MINIMUM_IOS_MAJOR} or later."
        )

    device = best[1]
    print(device["udid"])
    print(f"Selected {device['name']} ({device['udid']})", file=sys.stderr)


if __name__ == "__main__":
    main()
