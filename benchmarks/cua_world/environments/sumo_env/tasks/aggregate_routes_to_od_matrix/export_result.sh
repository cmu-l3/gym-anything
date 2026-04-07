#!/bin/bash
echo "=== Exporting aggregate_routes_to_od_matrix result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Paths
OD_FILE="/home/ga/SUMO_Output/pasubio_hourly.od"
TXT_FILE="/home/ga/SUMO_Output/peak_od_pair.txt"

# 1. Check generated OD file
OD_EXISTS="false"
OD_CREATED="false"
OD_SIZE=0
if [ -f "$OD_FILE" ]; then
    OD_EXISTS="true"
    OD_SIZE=$(stat -c %s "$OD_FILE")
    OD_MTIME=$(stat -c %Y "$OD_FILE")
    if [ "$OD_MTIME" -gt "$TASK_START" ]; then
        OD_CREATED="true"
    fi
fi

# 2. Check and extract text file contents
TXT_EXISTS="false"
TXT_CREATED="false"
AGENT_O=""
AGENT_D=""
AGENT_TRIPS=""
if [ -f "$TXT_FILE" ]; then
    TXT_EXISTS="true"
    TXT_MTIME=$(stat -c %Y "$TXT_FILE")
    if [ "$TXT_MTIME" -gt "$TASK_START" ]; then
        TXT_CREATED="true"
    fi
    # Read first 3 lines, strip carriage returns
    read -r AGENT_O < <(sed -n '1p' "$TXT_FILE" | tr -d '\r')
    read -r AGENT_D < <(sed -n '2p' "$TXT_FILE" | tr -d '\r')
    read -r AGENT_TRIPS < <(sed -n '3p' "$TXT_FILE" | tr -d '\r')
fi

# 3. Calculate Ground Truth dynamically
# We extract this directly from the source XML to ensure ground truth is 100% accurate,
# completely independent of the agent's usage of route2OD.py.
GT_JSON=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
from collections import defaultdict
import json

route_file = "/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio.rou.xml"
counts = defaultdict(int)
routes = {}

try:
    tree = ET.parse(route_file)
    root = tree.getroot()

    # Pass 1: Collect standalone routes referenced by vehicles
    for route in root.findall('route'):
        r_id = route.get('id')
        edges = route.get('edges', '').split()
        if r_id and edges:
            routes[r_id] = edges

    # Pass 2: Count valid trips within the 0-3600 interval
    for vehicle in root.findall('vehicle'):
        depart = float(vehicle.get('depart', 0))
        if 0 <= depart < 3600:
            edges = []
            
            # Case A: Inline route
            r_node = vehicle.find('route')
            if r_node is not None:
                edges = r_node.get('edges', '').split()
            
            # Case B: Referenced route
            elif vehicle.get('route'):
                edges = routes.get(vehicle.get('route'), [])

            # Tally OD pair
            if edges:
                o = edges[0]
                d = edges[-1]
                counts[(o, d)] += 1

    max_trips = max(counts.values()) if counts else 0
    # Capture all pairs that tie for the maximum (usually just 1, but ties are mathematically possible)
    peak_pairs = [[o, d] for (o, d), c in counts.items() if c == max_trips]
    
    print(json.dumps({
        "success": True, 
        "max_trips": max_trips, 
        "peak_pairs": peak_pairs
    }))
except Exception as e:
    print(json.dumps({
        "success": False, 
        "max_trips": 0, 
        "peak_pairs": [], 
        "error": str(e)
    }))
PYEOF
)

# 4. Package results into export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "od_exists": $OD_EXISTS,
    "od_created_during_task": $OD_CREATED,
    "od_size_bytes": $OD_SIZE,
    "txt_exists": $TXT_EXISTS,
    "txt_created_during_task": $TXT_CREATED,
    "agent_o": "$(echo "$AGENT_O" | sed 's/"/\\"/g')",
    "agent_d": "$(echo "$AGENT_D" | sed 's/"/\\"/g')",
    "agent_trips": "$(echo "$AGENT_TRIPS" | sed 's/"/\\"/g')",
    "ground_truth": $GT_JSON
}
EOF

# Move securely
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="