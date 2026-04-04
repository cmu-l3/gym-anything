#!/bin/bash
echo "=== Exporting Correct Reversed Polarity Result ==="

source /workspace/scripts/task_utils.sh

# Stop the simulation to prevent noise during verification
if [ -f /tmp/sensor_sim.pid ]; then
    kill $(cat /tmp/sensor_sim.pid) 2>/dev/null || true
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Get Input Processing Chain
# We need to see the order of processes for 'garage_solar' -> 'power'
# processList is often stored as a string "processID:arg,processID:arg" in the input table
# OR in a separate input_process table depending on Emoncms version.
# We will inspect the `input` table's `processList` column which is the most common storage.

INPUT_JSON=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e \
    "SELECT processList FROM input WHERE nodeid='garage_solar' AND name='power'" 2>/dev/null || echo "")

echo "Raw Process List: $INPUT_JSON"

# 2. Get Feed IDs and Names for verification
# We export the feeds table to map IDs in the process list to names
docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -e \
    "SELECT id, name, tag, engine, value FROM feeds" > /tmp/feeds_dump.txt 2>/dev/null

# 3. Get Process List Human Readable (Simulation)
# We map standard Emoncms process IDs:
# 1 = Log to feed
# 2 = Scale (x)
# 4 = Power to kWh
# 5 = Power to kWh/d (deprecated sometimes, but check)

# Create a Python script to parse this into JSON
cat > /tmp/parse_results.py << 'PYEOF'
import json
import csv
import sys

def parse_process_list(plist_str):
    if not plist_str:
        return []
    # Format: "1:12,2:-1" (ProcessID:Arg)
    try:
        items = plist_str.split(',')
        processes = []
        for item in items:
            if ':' in item:
                pid, arg = item.split(':')
                processes.append({"id": int(pid), "arg": arg})
        return processes
    except:
        return []

# Read inputs
try:
    with open('/tmp/process_list_raw.txt', 'r') as f:
        raw_plist = f.read().strip()
except:
    raw_plist = ""

# Read feeds
feeds = {}
try:
    with open('/tmp/feeds_dump.txt', 'r') as f:
        reader = csv.DictReader(f, delimiter='\t')
        for row in reader:
            feeds[row['id']] = row
except:
    pass

# Parse chain
chain = parse_process_list(raw_plist)
enriched_chain = []

for step in chain:
    pid = step['id']
    arg = step['arg']
    desc = "Unknown"
    target = arg
    
    if pid == 1:
        desc = "Log to feed"
        if arg in feeds:
            target = feeds[arg]['name']
    elif pid == 2:
        desc = "Scale"
        target = arg # The multiplier
    elif pid == 4 or pid == 5:
        desc = "Power to kWh"
        if arg in feeds:
            target = feeds[arg]['name']
            
    enriched_chain.append({
        "process_id": pid,
        "description": desc,
        "target": target,
        "raw_arg": arg
    })

# Check specific feeds
solar_yield = next((f for f in feeds.values() if f['name'] == 'solar_yield'), None)
solar_energy = next((f for f in feeds.values() if f['name'] == 'solar_energy'), None)

result = {
    "process_chain": enriched_chain,
    "feeds": {
        "solar_yield": {
            "exists": bool(solar_yield),
            "value": float(solar_yield['value']) if solar_yield else 0,
            "engine": solar_yield['engine'] if solar_yield else None
        },
        "solar_energy": {
            "exists": bool(solar_energy),
            "value": float(solar_energy['value']) if solar_energy else 0,
            "engine": solar_energy['engine'] if solar_energy else None
        }
    },
    "timestamp": int(time.time())
}

import time
print(json.dumps(result))
PYEOF

# Save raw process list for Python
echo "$INPUT_JSON" > /tmp/process_list_raw.txt

# Run parser
python3 /tmp/parse_results.py > /tmp/parsed_result.json

# Merge with task info
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat /tmp/parsed_result.json > "$TEMP_JSON"

# Save result
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export complete ==="