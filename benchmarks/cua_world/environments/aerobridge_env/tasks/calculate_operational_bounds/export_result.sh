#!/bin/bash
# export_result.sh - Post-task export for calculate_operational_bounds
# Calculates the GROUND TRUTH bounding box and compares it with agent output

echo "=== Exporting task results ==="

# 1. Record basic info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/operational_bounds.json"
SCRIPT_PATH="/home/ga/calc_bounds.py"

# 2. Check for agent files
OUTPUT_EXISTS="false"
OUTPUT_CONTENT="{}"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    # Basic check if it uses Django
    if grep -q "django" "$SCRIPT_PATH" || grep -q "FlightPlan" "$SCRIPT_PATH"; then
        SCRIPT_LOOKS_VALID="true"
    else
        SCRIPT_LOOKS_VALID="false"
    fi
else
    SCRIPT_LOOKS_VALID="false"
fi

# 3. Calculate GROUND TRUTH using the same environment
# We run a python script to inspect the database and calculate the actual bounds
echo "Calculating ground truth..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

GT_JSON=$(/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django, json, math

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

def get_coords_from_geometry(geo):
    """Recursively extract all [lon, lat] pairs from GeoJSON-like structure"""
    coords = []
    if isinstance(geo, dict):
        if 'coordinates' in geo:
            return get_coords_from_geometry(geo['coordinates'])
        # Handle FeatureCollection/Feature if present (unlikely in raw field but possible)
        return []
    elif isinstance(geo, list):
        # Check if this is a coordinate pair [lon, lat]
        if len(geo) == 2 and isinstance(geo[0], (int, float)) and isinstance(geo[1], (int, float)):
            return [geo]
        # Otherwise recurse
        for item in geo:
            coords.extend(get_coords_from_geometry(item))
    return coords

try:
    try:
        from gcs_operations.models import FlightPlan
    except ImportError:
        from gcs_operations.models import GCSFlightPlan as FlightPlan

    min_lat = float('inf')
    max_lat = float('-inf')
    min_lon = float('inf')
    max_lon = float('-inf')
    
    count = 0
    
    for plan in FlightPlan.objects.all():
        # Inspect fields to find geometry
        # Usually 'geometry' field contains the JSON/GeoJSON
        raw_geo = None
        if hasattr(plan, 'geometry'):
            raw_geo = plan.geometry
        elif hasattr(plan, 'geo_json'):
            raw_geo = plan.geo_json
            
        if not raw_geo:
            continue
            
        # Parse if string
        if isinstance(raw_geo, str):
            try:
                geo_data = json.loads(raw_geo)
            except:
                continue
        else:
            geo_data = raw_geo
            
        # Extract coordinates
        points = get_coords_from_geometry(geo_data)
        
        for p in points:
            # GeoJSON is [lon, lat]
            lon, lat = float(p[0]), float(p[1])
            
            if lat < min_lat: min_lat = lat
            if lat > max_lat: max_lat = lat
            if lon < min_lon: min_lon = lon
            if lon > max_lon: max_lon = lon
            count += 1

    if count == 0:
        # Fallback if DB empty (should not happen due to setup)
        result = {"error": "No coordinates found in database"}
    else:
        result = {
            "min_lat": min_lat,
            "max_lat": max_lat,
            "min_lon": min_lon,
            "max_lon": max_lon,
            "points_processed": count
        }
    
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
)

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "script_exists": $SCRIPT_EXISTS,
    "script_looks_valid": $SCRIPT_LOOKS_VALID,
    "agent_output_content": $OUTPUT_CONTENT,
    "ground_truth": $GT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="