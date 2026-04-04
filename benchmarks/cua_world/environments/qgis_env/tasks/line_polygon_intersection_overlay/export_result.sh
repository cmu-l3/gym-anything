#!/bin/bash
echo "=== Exporting line_polygon_intersection_overlay result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi

take_screenshot /tmp/task_end.png

EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_FILE="$EXPORT_DIR/roads_by_zone.geojson"

INITIAL_COUNT=$(cat /tmp/initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Analyze the output file
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
ANALYSIS_JSON='{}'

# Check if file exists (or alternative name)
if [ ! -f "$EXPECTED_FILE" ]; then
    # Look for likely alternatives
    ALT_FILE=$(find "$EXPORT_DIR" -name "*intersection*" -o -name "*overlay*" -o -name "roads_split.geojson" | head -1)
    if [ -n "$ALT_FILE" ]; then
        EXPECTED_FILE="$ALT_FILE"
    fi
fi

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")

    # Python script to analyze the GeoJSON content depth
    ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys

filepath = r"'"$EXPECTED_FILE"'"
try:
    with open(filepath, 'r') as f:
        data = json.load(f)

    if data.get("type") != "FeatureCollection":
        print(json.dumps({"valid": False, "error": "Not a FeatureCollection"}))
        sys.exit(0)

    features = data.get("features", [])
    feature_count = len(features)

    # Geometry checks
    all_lines = True
    valid_geoms = True
    
    # Attribute checks
    # We expect attributes from LINES (e.g., "type": "highway") 
    # AND from POLYGONS (e.g., "area_sqkm": 10.5 or "name": "Area A")
    has_line_attr = False
    has_poly_attr = False
    
    zones_found = set()

    for feat in features:
        geom = feat.get("geometry", {})
        if geom is None:
            valid_geoms = False
            continue
            
        gtype = geom.get("type", "")
        if "Line" not in gtype:
            all_lines = False
            
        props = feat.get("properties", {})
        if not props:
            continue
            
        # Check for Line attributes (look for 'highway' or 'secondary' in type)
        # Or check keys like 'type' (which exists in sample_lines)
        vals = [str(v).lower() for v in props.values()]
        keys = [str(k).lower() for k in props.keys()]
        
        if "highway" in vals or "secondary" in vals:
            has_line_attr = True
            
        # Check for Polygon attributes
        # sample_polygon has 'area_sqkm'
        if "area_sqkm" in keys or any("area" in k and "sqkm" in k for k in keys):
            has_poly_attr = True
            
        # Collect zone names found
        for v in props.values():
            s_val = str(v)
            if "Area A" in s_val:
                zones_found.add("Area A")
            if "Area B" in s_val:
                zones_found.add("Area B")

    result = {
        "valid": True,
        "feature_count": feature_count,
        "all_lines": all_lines,
        "valid_geoms": valid_geoms,
        "has_line_attr": has_line_attr,
        "has_poly_attr": has_poly_attr,
        "zones_found": list(zones_found)
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
fi

# Close QGIS cleanly
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "initial_export_count": $INITIAL_COUNT,
    "current_export_count": $CURRENT_COUNT,
    "task_start_time": $TASK_START_TIME,
    "file_exists": $FILE_EXISTS,
    "file_path": "$EXPECTED_FILE",
    "file_size_bytes": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="