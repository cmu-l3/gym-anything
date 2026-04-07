#!/bin/bash
echo "=== Exporting lidar_raycast_mapping Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/lidar_raycast_mapping_start_ts 2>/dev/null || echo "0")

SCENE="/home/ga/Documents/CoppeliaSim/exports/mapping_arena.ttt"
CSV="/home/ga/Documents/CoppeliaSim/exports/lidar_point_cloud.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/mapping_report.json"

# Take final screenshot
take_screenshot /tmp/lidar_raycast_mapping_end.png

# 1. Check Scene File
TTT_EXISTS="false"
TTT_IS_NEW="false"
TTT_SIZE=0
if [ -f "$SCENE" ]; then
    TTT_EXISTS="true"
    TTT_MTIME=$(stat -c %Y "$SCENE" 2>/dev/null || echo "0")
    [ "$TTT_MTIME" -gt "$TASK_START" ] && TTT_IS_NEW="true"
    TTT_SIZE=$(stat -c %s "$SCENE" 2>/dev/null || echo "0")
fi

# 2. Check and parse CSV File
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_STATS='{"valid": false}'

if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW="true"

    CSV_STATS=$(python3 << 'PYEOF'
import csv, json, sys

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/lidar_point_cloud.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    if not rows:
        print(json.dumps({"valid": False, "reason": "empty"}))
        sys.exit(0)

    headers = [h.strip().lower() for h in rows[0].keys()]
    has_headers = all(k in headers for k in ['angle_deg', 'distance_m', 'hit_x', 'hit_y'])

    hx = next((h for h in rows[0].keys() if h.strip().lower() == 'hit_x'), None)
    hy = next((h for h in rows[0].keys() if h.strip().lower() == 'hit_y'), None)
    hd = next((h for h in rows[0].keys() if h.strip().lower() in ['distance_m', 'distance']), None)

    xs, ys = [], []
    internal_hits = 0

    if hx and hy and hd:
        for r in rows:
            try:
                x, y, d = float(r[hx]), float(r[hy]), float(r[hd])
                xs.append(x)
                ys.append(y)
                if d < 2.5:
                    internal_hits += 1
            except ValueError:
                pass

    if xs and ys:
        print(json.dumps({
            "valid": True,
            "has_headers": has_headers,
            "row_count": len(xs),
            "max_x": max(xs), "min_x": min(xs),
            "max_y": max(ys), "min_y": min(ys),
            "internal_hits": internal_hits
        }))
    else:
        print(json.dumps({"valid": False, "reason": "no_valid_data"}))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
fi

# 3. Check JSON Report
JSON_EXISTS="false"
JSON_IS_NEW="false"
JSON_STATS='{"valid": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW="true"

    JSON_STATS=$(python3 << 'PYEOF'
import json, sys
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/mapping_report.json') as f:
        d = json.load(f)
    has_fields = all(k in d for k in ['total_rays', 'valid_hits'])
    print(json.dumps({'valid': True, 'has_fields': has_fields}))
except Exception as e:
    print(json.dumps({'valid': False, 'error': str(e)}))
PYEOF
    )
fi

# Compile final result
TEMP_JSON=$(mktemp /tmp/lidar_raycast_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "ttt": {
        "exists": $TTT_EXISTS,
        "is_new": $TTT_IS_NEW,
        "size_bytes": $TTT_SIZE
    },
    "csv": {
        "exists": $CSV_EXISTS,
        "is_new": $CSV_IS_NEW,
        "stats": $CSV_STATS
    },
    "json": {
        "exists": $JSON_EXISTS,
        "is_new": $JSON_IS_NEW,
        "stats": $JSON_STATS
    }
}
EOF

rm -f /tmp/lidar_raycast_mapping_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/lidar_raycast_mapping_result.json
chmod 666 /tmp/lidar_raycast_mapping_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="