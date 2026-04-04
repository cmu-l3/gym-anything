#!/bin/bash
echo "=== Exporting create_vector_grid results ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

# 1. Capture final state
take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Locate output file
EXPORTS_DIR="/home/ga/GIS_Data/exports"
EXPECTED_PATH="$EXPORTS_DIR/study_area_grid.geojson"
ACTUAL_PATH=""

if [ -f "$EXPECTED_PATH" ]; then
    ACTUAL_PATH="$EXPECTED_PATH"
else
    # Check for alternative names
    ALT_PATH=$(find "$EXPORTS_DIR" -name "*grid*.geojson" -newermt "@$TASK_START" 2>/dev/null | head -1)
    if [ -n "$ALT_PATH" ]; then
        ACTUAL_PATH="$ALT_PATH"
    fi
fi

# 3. Analyze output with Python
# We generate a detailed JSON report to be read by the verifier
REPORT_FILE="/tmp/task_result.json"

if [ -n "$ACTUAL_PATH" ] && [ -f "$ACTUAL_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$ACTUAL_PATH" 2>/dev/null || echo "0")
    
    # Run Python analysis script
    python3 << PYEOF > "$REPORT_FILE"
import json
import os
import sys

result = {
    "file_exists": True,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "valid_geojson": False,
    "is_polygon": False,
    "feature_count": 0,
    "bounds_correct": False,
    "cell_size_correct": False,
    "avg_cell_width": 0,
    "avg_cell_height": 0,
    "bbox": None
}

try:
    with open("$ACTUAL_PATH", 'r') as f:
        data = json.load(f)
        
    result["valid_geojson"] = True
    
    if data.get("type") == "FeatureCollection":
        features = data.get("features", [])
        result["feature_count"] = len(features)
        
        if len(features) > 0:
            # Check geometry type
            geoms = [f.get("geometry", {}) for f in features]
            types = [g.get("type") for g in geoms]
            
            # Allow Polygon or MultiPolygon
            poly_count = sum(1 for t in types if t in ["Polygon", "MultiPolygon"])
            result["is_polygon"] = (poly_count == len(features))
            
            # Analyze coordinates to determine grid extent and cell size
            all_x = []
            all_y = []
            widths = []
            heights = []
            
            for g in geoms:
                coords = g.get("coordinates", [])
                if not coords: continue
                
                # Extract exterior ring
                ring = coords[0] if g["type"] == "Polygon" else coords[0][0]
                
                xs = [p[0] for p in ring]
                ys = [p[1] for p in ring]
                
                if xs and ys:
                    w = max(xs) - min(xs)
                    h = max(ys) - min(ys)
                    widths.append(w)
                    heights.append(h)
                    all_x.extend(xs)
                    all_y.extend(ys)
            
            # Calculate metrics
            if all_x and all_y:
                min_x, max_x = min(all_x), max(all_x)
                min_y, max_y = min(all_y), max(all_y)
                
                result["bbox"] = [min_x, min_y, max_x, max_y]
                
                # Expected extent: approx -122.5 to -121.9, 37.5 to 37.8
                # Allow some tolerance
                if (min_x <= -122.5 + 0.05 and max_x >= -121.9 - 0.05 and
                    min_y <= 37.5 + 0.05 and max_y >= 37.8 - 0.05):
                    result["bounds_correct"] = True
            
            if widths and heights:
                avg_w = sum(widths) / len(widths)
                avg_h = sum(heights) / len(heights)
                result["avg_cell_width"] = avg_w
                result["avg_cell_height"] = avg_h
                
                # Expected size: 0.1 deg
                # Allow tolerance (e.g. 0.09 to 0.11)
                if (0.09 <= avg_w <= 0.11) and (0.09 <= avg_h <= 0.11):
                    result["cell_size_correct"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

else
    # File not found
    cat > "$REPORT_FILE" << EOF
{
    "file_exists": false,
    "file_path": null,
    "file_size": 0,
    "valid_geojson": false,
    "feature_count": 0
}
EOF
fi

# 4. Check application state
APP_RUNNING=$(pgrep -f "qgis" > /dev/null && echo "true" || echo "false")

# Update report with metadata
# Use a temporary file to merge JSONs safely
TEMP_MERGE=$(mktemp)
python3 -c "
import json
with open('$REPORT_FILE', 'r') as f: data = json.load(f)
data['app_running'] = $APP_RUNNING
data['task_start'] = $TASK_START
data['task_end'] = $TASK_END
print(json.dumps(data))
" > "$TEMP_MERGE"
mv "$TEMP_MERGE" "$REPORT_FILE"

# Ensure permissions
chmod 666 "$REPORT_FILE" 2>/dev/null || true

# Close QGIS
if [ "$APP_RUNNING" = "true" ]; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

echo "Result saved to $REPORT_FILE"
cat "$REPORT_FILE"
echo "=== Export complete ==="