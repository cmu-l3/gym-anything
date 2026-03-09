#!/bin/bash
# export_result.sh — Verify corrections and export results

source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# 1. Gather Context
# -----------------------------------------------------------------------
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
APIKEY=$(get_apikey_write)
METADATA_FILE="/var/lib/emoncms_task/spike_metadata.json"

if [ ! -f "$METADATA_FILE" ]; then
    echo "ERROR: Metadata file not found. Setup may have failed."
    echo '{"error": "metadata_missing"}' > /tmp/task_result.json
    exit 0
fi

# 2. Verify Spikes
# -----------------------------------------------------------------------
# We use Python to query the specific timestamps and verify values
python3 << PYEOF
import json
import urllib.request
import sys
import os

apikey = "${APIKEY}"
base_url = "${EMONCMS_URL}"
task_start = int("${TASK_START}")
task_end = int("${TASK_END}")

with open("${METADATA_FILE}", "r") as f:
    meta = json.load(f)

feed_id = meta["feed_id"]
spikes = meta["spikes"]

results = {
    "task_start": task_start,
    "task_end": task_end,
    "feed_id": feed_id,
    "spikes_fixed": 0,
    "total_spikes": len(spikes),
    "spike_details": [],
    "feed_clean": False,
    "screenshot_path": "/tmp/task_final.png"
}

print(f"Verifying {len(spikes)} spikes for feed {feed_id}...")

for spike in spikes:
    ts = spike["timestamp"]
    # Query specific timestamp
    # Note: feed/data.json returns closest points. We ask for a small window.
    # Window: ts - 5s to ts + 5s
    url = f"{base_url}/feed/data.json?id={feed_id}&start={(ts-5)*1000}&end={(ts+5)*1000}&interval=1&apikey={apikey}"
    
    val = None
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            # Data format: [[time_ms, value], ...]
            # Find closest to ts*1000
            for point in data:
                if abs(point[0] - ts*1000) < 5000: # Within 5s
                    val = point[1]
                    break
    except Exception as e:
        print(f"Error querying {ts}: {e}")

    status = "unknown"
    if val is None:
        status = "missing"
    elif val > 5000:
        status = "failed_high"
    elif val < 0:
        status = "failed_negative"
    elif val > 4000:
        status = "failed_too_high" # Valid range is 0-4000
    else:
        status = "fixed"
        results["spikes_fixed"] += 1
    
    results["spike_details"].append({
        "timestamp": ts,
        "value_found": val,
        "status": status
    })

# 3. Check for any remaining spikes (Full Feed Scan)
# -----------------------------------------------------------------------
# Scan the whole day range to ensure no other spikes (or missed spikes)
now_ts = int(time.time())
start_ts = now_ts - 86400
url_scan = f"{base_url}/feed/data.json?id={feed_id}&start={start_ts*1000}&end={now_ts*1000}&interval=60&apikey={apikey}"

max_val_found = 0
try:
    with urllib.request.urlopen(url_scan, timeout=10) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        for p in data:
            if p[1] is not None:
                if p[1] > max_val_found:
                    max_val_found = p[1]
except Exception as e:
    print(f"Scan error: {e}")

if max_val_found < 5000:
    results["feed_clean"] = True
else:
    results["feed_clean"] = False
    results["max_val_remaining"] = max_val_found

# Output JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)

print("Verification complete.")
PYEOF

# 3. Final Artifacts
# -----------------------------------------------------------------------
take_screenshot /tmp/task_final.png

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

cat /tmp/task_result.json
echo "=== Export complete ==="