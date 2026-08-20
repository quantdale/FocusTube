#!/usr/bin/env bash
set -euo pipefail

xcrun simctl list runtimes
xcrun simctl list devices available

python3 - <<'PY2'
import json, subprocess, sys
raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True)
data = json.loads(raw)
candidates = []
for runtime, devices in data.get("devices", {}).items():
    if "iOS-26" not in runtime:
        continue
    for d in devices:
        if d.get("isAvailable") and d.get("name", "").startswith("iPhone"):
            candidates.append((runtime, d["name"], d["udid"]))
if not candidates:
    # Fall back to any available iOS iPhone runtime, but report it explicitly.
    for runtime, devices in data.get("devices", {}).items():
        if "iOS" not in runtime:
            continue
        for d in devices:
            if d.get("isAvailable") and d.get("name", "").startswith("iPhone"):
                candidates.append((runtime, d["name"], d["udid"]))
if not candidates:
    sys.exit("No available iPhone Simulator found")
runtime, name, udid = candidates[0]
print(f"Selected simulator: {name} {runtime} {udid}", file=sys.stderr)
with open("/tmp/focustube_simulator_udid", "w") as f:
    f.write(udid)
PY2

cat /tmp/focustube_simulator_udid
