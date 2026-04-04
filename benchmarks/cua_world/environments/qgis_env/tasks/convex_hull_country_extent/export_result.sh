#!/bin/bash
echo "=== Exporting Convex Hull task result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EXPORT_DIR="/home/ga/GIS_Data/exports"
GEOJSON_PATH="$EXPORT_DIR/australia_convex_hull.geojson"
REPORT_PATH="$EXPORT_DIR/australia_hull_report.txt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if app was running
APP_RUNNING="false"
if is_qgis_running; then
    APP_RUNNING="true"
    # Close QGIS gracefully
    safe_xdotool ga :1 key ctrl+q
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# --- Analyze GeoJSON Output ---
GEOJSON_EXISTS="false"
GEOJSON_VALID="false"
IS_POLYGON="false"
FEATURE_COUNT=0
BBOX="[]"
GEOJSON_AREA=0

if [ -f "$GEOJSON_PATH" ]; then
    GEOJSON_MTIME=$(stat -c %Y "$GEOJSON_PATH" 2>/dev/null || echo "0")
    if [ "$GEOJSON_MTIME" -gt "$TASK_START" ]; then
        GEOJSON_EXISTS="true"
        
        # Python script to validate GeoJSON and calculate basic metrics
        # We use simple geometry calculation here; accurate geodetic area is complex but 
        # approximate planar area on lat/lon gives us a sanity check order of magnitude.
        ANALYSIS=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/GIS_Data/exports/australia_convex_hull.geojson") as f:
        data = json.load(f)

    if data.get("type") == "FeatureCollection":
        features = data.get("features", [])
        count = len(features)
        
        is_poly = False
        bounds = [180, 90, -180, -90] # minx, miny, maxx, maxy
        
        if count > 0:
            # Check geometry type of first feature
            geom_type = features[0].get("geometry", {}).get("type", "")
            if geom_type in ["Polygon", "MultiPolygon"]:
                is_poly = True
                
                # Calculate rough bounding box
                coords = features[0]["geometry"]["coordinates"]
                # Flatten coordinates recursively to list of points
                def flatten(lst):
                    if len(lst) > 0 and not isinstance(lst[0], list):
                        return [lst]
                    out = []
                    for item in lst:
                        out.extend(flatten(item))
                    return out
                
                all_pts = flatten(coords)
                xs = [p[0] for p in all_pts]
                ys = [p[1] for p in all_pts]
                if xs and ys:
                    bounds = [min(xs), min(ys), max(xs), max(ys)]

        print(f"valid=true")
        print(f"count={count}")
        print(f"is_poly={'true' if is_poly else 'false'}")
        print(f"bbox=[{bounds[0]},{bounds[1]},{bounds[2]},{bounds[3]}]")
        
    else:
        print("valid=false")
        print("count=0")
        print("is_poly=false")
        print("bbox=[]")

except Exception as e:
    print("valid=false")
    print("count=0")
    print("is_poly=false")
    print("bbox=[]")
PYEOF
        )
        
        # Eval the output variables
        eval "$ANALYSIS"
        GEOJSON_VALID="${valid:-false}"
        FEATURE_COUNT="${count:-0}"
        IS_POLYGON="${is_poly:-false}"
        BBOX="${bbox:-[]}"
    fi
fi

# --- Analyze Report Output ---
REPORT_EXISTS="false"
REPORT_CONTENT=""
EXTRACTED_AREA=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_EXISTS="true"
        # Read content (limit size)
        REPORT_CONTENT=$(head -n 5 "$REPORT_PATH")
        
        # Extract number from report (handle commas, scientific notation)
        # Looking for something like "7,692,000" or "7.69e6"
        EXTRACTED_AREA=$(echo "$REPORT_CONTENT" | grep -oE '[0-9,]+(\.[0-9]+)?(e\+?[0-9]+)?' | tr -d ',' | head -1)
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "geojson_exists": $GEOJSON_EXISTS,
    "geojson_valid": $GEOJSON_VALID,
    "geojson_feature_count": $FEATURE_COUNT,
    "geojson_is_polygon": $IS_POLYGON,
    "geojson_bbox": $BBOX,
    "report_exists": $REPORT_EXISTS,
    "report_extracted_area": "${EXTRACTED_AREA:-0}",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="