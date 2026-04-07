#!/bin/bash
echo "=== Exporting world_geodetic_audit result ==="

# Define paths
CSV_PATH="/home/ga/Documents/world_catalog.csv"
REPORT_PATH="/home/ga/Documents/geodetic_audit_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check CSV File
CSV_EXISTS="false"
CSV_MODIFIED="false"
CSV_CONTENT=""

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$CSV_PATH")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED="true"
    fi
    # Read content safely (max 50KB)
    CSV_CONTENT=$(head -c 50000 "$CSV_PATH" | base64 -w 0)
fi

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_MODIFIED="false"
REPORT_LINE_COUNT=0
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        REPORT_MODIFIED="true"
    fi
    REPORT_LINE_COUNT=$(wc -l < "$REPORT_PATH")
    # Read content safely
    REPORT_CONTENT=$(head -c 50000 "$REPORT_PATH" | base64 -w 0)
fi

# 3. Generate Ground Truth (Programmatically parse the actual world files)
# This ensures we grade against the actual installed data, even if it changes.
echo "Generating ground truth..."
python3 -c "
import os
import glob
import json
import math
import configparser

world_dir = '/opt/bridgecommand/World'
worlds = []

# Simple INI parser that handles files without headers
def parse_ini_file(filepath):
    data = {}
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if '=' in line and not line.startswith(';'):
                    parts = line.split('=', 1)
                    key = parts[0].strip()
                    val = parts[1].strip().split(';')[0].strip() # Remove comments
                    data[key] = val
    except Exception as e:
        print(f'Error reading {filepath}: {e}')
    return data

if os.path.exists(world_dir):
    for entry in os.scandir(world_dir):
        if entry.is_dir():
            world_name = entry.name
            # Look for ini files
            ini_path = os.path.join(entry.path, 'terrain.ini')
            # Sometimes config might be in other ini files, but terrain.ini is standard
            if not os.path.exists(ini_path):
                # Try finding any ini file
                inis = glob.glob(os.path.join(entry.path, '*.ini'))
                if inis:
                    ini_path = inis[0]
            
            if os.path.exists(ini_path):
                params = parse_ini_file(ini_path)
                
                # Extract float/int values safely
                try:
                    lat = float(params.get('TerrainLat', 0))
                    lon = float(params.get('TerrainLong', 0))
                    lat_ext = float(params.get('TerrainLatExtent', 0))
                    lon_ext = float(params.get('TerrainLongExtent', 0))
                    width = int(params.get('MapWidth', 0))
                    height = int(params.get('MapHeight', 0))
                    depth = float(params.get('SeaMaxDepth', 0))
                    
                    # Compute Ground Truth Metrics
                    mid_lat_rad = math.radians(lat + lat_ext/2)
                    nm_per_deg_lat = 60.0
                    nm_per_deg_lon = 60.0 * math.cos(mid_lat_rad)
                    
                    area_sq_nm = (lat_ext * nm_per_deg_lat) * (lon_ext * nm_per_deg_lon)
                    
                    m_per_deg_lat = 111120.0
                    m_per_deg_lon = 111120.0 * math.cos(mid_lat_rad)
                    
                    res_lat = (lat_ext * m_per_deg_lat) / height if height > 0 else 0
                    res_lon = (lon_ext * m_per_deg_lon) / width if width > 0 else 0
                    avg_res = (res_lat + res_lon) / 2
                    
                    worlds.append({
                        'WorldName': world_name,
                        'TerrainLat': lat,
                        'TerrainLong': lon,
                        'LatExtent': lat_ext,
                        'LongExtent': lon_ext,
                        'MapWidth': width,
                        'MapHeight': height,
                        'SeaMaxDepth': depth,
                        'AreaSqNm': area_sq_nm,
                        'ResolutionMetersPerPixel': avg_res
                    })
                except ValueError:
                    continue

print(json.dumps(worlds))
" > /tmp/ground_truth_worlds.json

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "csv": {
        "exists": $CSV_EXISTS,
        "modified": $CSV_MODIFIED,
        "content_base64": "$CSV_CONTENT"
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "modified": $REPORT_MODIFIED,
        "line_count": $REPORT_LINE_COUNT,
        "content_base64": "$REPORT_CONTENT"
    },
    "ground_truth_path": "/tmp/ground_truth_worlds.json"
}
EOF

# Move and set permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="