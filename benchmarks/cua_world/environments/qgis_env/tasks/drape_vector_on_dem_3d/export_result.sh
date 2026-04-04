#!/bin/bash
echo "=== Exporting Drape Vector Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if file was created/modified during task
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_OUTPUT="$EXPORT_DIR/trail_3d.gpkg"
ALT_OUTPUT="$EXPORT_DIR/trail_3d.geojson"

# Determine which output file exists (prefer GPKG as requested, but accept GeoJSON)
OUTPUT_FILE=""
if [ -f "$EXPECTED_OUTPUT" ]; then
    OUTPUT_FILE="$EXPECTED_OUTPUT"
elif [ -f "$ALT_OUTPUT" ]; then
    OUTPUT_FILE="$ALT_OUTPUT"
else
    # Check for any new file in exports
    NEWEST=$(find "$EXPORT_DIR" -type f \( -name "*.gpkg" -o -name "*.geojson" \) -newermt "@$TASK_START" 2>/dev/null | head -1)
    if [ -n "$NEWEST" ]; then
        OUTPUT_FILE="$NEWEST"
    fi
fi

# Analyze the output file using Python (GDAL/OGR)
# We embed the analysis script to run inside the container
ANALYSIS_JSON="{}"
if [ -n "$OUTPUT_FILE" ]; then
    ANALYSIS_JSON=$(python3 << PYEOF
import json
import os
import sys

try:
    from osgeo import ogr
except ImportError:
    # Fallback if osgeo not installed (unlikely in qgis env)
    print(json.dumps({"error": "osgeo module missing"}))
    sys.exit(0)

file_path = "$OUTPUT_FILE"
result = {
    "file_exists": True,
    "file_path": file_path,
    "is_valid": False,
    "geom_type": "Unknown",
    "is_3d": False,
    "has_z_values": False,
    "z_min": 0,
    "z_max": 0,
    "vertex_count": 0,
    "feature_count": 0
}

try:
    ds = ogr.Open(file_path)
    if ds:
        layer = ds.GetLayer()
        result["feature_count"] = layer.GetFeatureCount()
        
        if result["feature_count"] > 0:
            feat = layer.GetNextFeature()
            geom = feat.GetGeometryRef()
            
            if geom:
                result["is_valid"] = True
                result["geom_type"] = geom.GetGeometryName()
                
                # Check 3D status
                # 2.5D types usually have '25D' in name or Is3D() returns true
                # Note: OGR wkbLineString25D logic
                wkb_type = geom.GetGeometryType()
                # 0x80000000 is the 2.5D flag in some OGR versions, or check Is3D()
                if geom.Is3D(): 
                    result["is_3d"] = True
                
                # Check actual Z values
                # GetPoints returns [(x,y,z), ...] if 3D
                points = geom.GetPoints()
                result["vertex_count"] = len(points)
                
                z_vals = []
                for p in points:
                    if len(p) > 2:
                        z_vals.append(p[2])
                
                if z_vals:
                    result["z_min"] = min(z_vals)
                    result["z_max"] = max(z_vals)
                    # Check if we have non-trivial Z values (not just flat 0)
                    if max(z_vals) > 0.1 or min(z_vals) < -0.1:
                        result["has_z_values"] = True
                else:
                    # Try to parse WKT if GetPoints fails to return tuples of 3
                    wkt = geom.ExportToWkt()
                    # Look for something like (19.02 -34.02 123.4)
                    pass

    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e), "file_exists": True}))
PYEOF
    )
else
    ANALYSIS_JSON='{"file_exists": false}'
fi

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="