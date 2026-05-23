#!/usr/bin/env python3
"""Pick the first available iOS simulator and emit an xcodebuild -destination string.

Prefers iPhones, prints "platform=iOS Simulator,name=<name>,OS=<version>"
to stdout. Used by .github/workflows/ios.yml.
"""

from __future__ import annotations

import json
import subprocess
import sys


def main() -> int:
    out = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        text=True,
    )
    devices = json.loads(out)["devices"]
    for runtime_key, runtime_devices in devices.items():
        if "iOS" not in runtime_key:
            continue
        # Normalize "com.apple.CoreSimulator.SimRuntime.iOS-26-5" -> "26.5"
        tail = runtime_key.split(".")[-1].replace("iOS-", "").replace("-", ".")
        for dev in runtime_devices:
            name = dev.get("name", "")
            if not name.startswith("iPhone"):
                continue
            print(f"platform=iOS Simulator,name={name},OS={tail}")
            return 0
    print("no iOS simulator available", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
