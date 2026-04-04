#!/bin/bash
set -e
echo "=== Exporting Points Along Lines results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/task_result.json"
OUTPUT_PATH="/home/ga/GIS_Data/exports/inspection_points.geojson"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Search for output file (also check alternative names/paths)
FOUND_FILE=""
if [ -f "$OUTPUT_PATH" ]; then
    FOUND_FILE="$OUTPUT_PATH"
else
    # Search for alternative filenames in export dir
    for alt in /home/ga/GIS_Data/exports/inspection*.geojson \
               /home/ga/GIS_Data/exports/points*.geojson \
               /home/ga/GIS_Data/exports/*along*.geojson; do
        if [ -f "$alt" ] 2>/dev/null; then
            FOUND_FILE="$alt"
            echo "Found alternative output: $alt"
            break
        fi
    done
fi

if [ -z "$FOUND_FILE" ]; then
    # Create empty result for verifier
    cat > "$RESULT_FILE" << EOF
{
    "file_exists": false,
    "error": "Output file not found"
}
EOF
    # Ensure permission
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
    echo "No output file found"
    cat "$RESULT_FILE"
    exit 0
fi

echo "Analyzing output file: $FOUND_FILE"

# Get file info
FILE_SIZE=$(stat -c%s "$FOUND_FILE" 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c%Y "$FOUND_FILE" 2>/dev/null || echo "0")
IS_NEW_FILE="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
    IS_NEW_FILE="true"
fi

# Parse GeoJSON with Python
# We use a python heredoc to perform complex validation (geometry check, bbox, etc)
python3 << PYEOF > "$RESULT_FILE"
import json
import sys
import os

result = {
    "file_exists": True,
    "file_path": "$FOUND_FILE",
    "file_size": $FILE_SIZE,
    "is_new_file": $( [ "$IS_NEW_FILE" = "true" ] && echo "True" || echo "False" ),
    "valid_geojson": False,
    "feature_count": 0,
    "all_point_geometry": False,
    "geometry_types": [],
    "coordinates_in_bbox": False,
    "spatial_distribution": False,
    "lon_range": [0, 0],
    "lat_range": [0, 0],
    "error": None
}

try:
    with open("$FOUND_FILE", 'r') as f:
        # Handle potential BOM or encoding issues
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            result['error'] = "Invalid JSON syntax"
            raise ValueError("Invalid JSON")
        
    if data.get('type') == 'FeatureCollection' and 'features' in data:
        result['valid_geojson'] = True
        features = data['features']
        result['feature_count'] = len(features)
        
        geom_types = set()
        all_lons = []
        all_lats = []
        all_point = True
        
        for feat in features:
            if feat.get('geometry') and feat['geometry'].get('type'):
                gtype = feat['geometry']['type']
                geom_types.add(gtype)
                
                if gtype not in ('Point', 'MultiPoint'):
                    all_point = False
                
                # Extract coordinates
                coords = feat['geometry'].get('coordinates', [])
                
                # Helper to flatten coordinates if needed
                def extract_pts(c, gt):
                    pts = []
                    if gt == 'Point':
                        if len(c) >= 2: pts.append(c)
                    elif gt == 'MultiPoint':
                        for p in c:
                            if len(p) >= 2: pts.append(p)
                    return pts

                points = extract_pts(coords, gtype)
                for p in points:
                    try:
                        all_lons.append(float(p[0]))
                        all_lats.append(float(p[1]))
                    except (ValueError, IndexError):
                        pass
            else:
                # Feature with no geometry or invalid structure
                pass
        
        result['all_point_geometry'] = all_point if len(features) > 0 else False
        result['geometry_types'] = list(geom_types)
        
        if all_lons and all_lats:
            min_lon, max_lon = min(all_lons), max(all_lons)
            min_lat, max_lat = min(all_lats), max(all_lats)
            result['lon_range'] = [min_lon, max_lon]
            result['lat_range'] = [min_lat, max_lat]
            
            # Check bounding box (Input lines span roughly -122.5 to -122.1, 37.5 to 37.8)
            # Allow some buffer
            bbox_ok = all(
                -123.0 <= lon <= -121.5 and 37.0 <= lat <= 38.5
                for lon, lat in zip(all_lons, all_lats)
            )
            result['coordinates_in_bbox'] = bbox_ok
            
            # Check spatial distribution
            # Points should not all be at the same location
            lon_span = max_lon - min_lon
            lat_span = max_lat - min_lat
            # With 0.05 spacing on ~0.4 deg line, we expect span > 0.05
            result['spatial_distribution'] = (lon_span > 0.05 or lat_span > 0.05)
        else:
            result['error'] = "No valid coordinates found"

    else:
        result['error'] = "Not a FeatureCollection"
        
except Exception as e:
    if result['error'] is None:
        result['error'] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="
cat "$RESULT_FILE"