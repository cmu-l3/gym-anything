#!/bin/bash
echo "=== Exporting select_by_location_export result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_SHP="/home/ga/gvsig_data/exports/african_cities.shp"
OUTPUT_DBF="/home/ga/gvsig_data/exports/african_cities.dbf"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence and timestamps
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE_BYTES=0

if [ -f "$OUTPUT_SHP" ] && [ -f "$OUTPUT_DBF" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$OUTPUT_SHP" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Run python script to analyze shapefile content
# We use a python script embedded here to avoid dependency issues on host verifier
cat > /tmp/analyze_shapefile.py << 'PYEOF'
import json
import sys
import os
import datetime

result = {
    "valid_shapefile": False,
    "feature_count": 0,
    "cities_found": [],
    "cities_forbidden_found": [],
    "bbox_valid": False,
    "geometry_type": "Unknown"
}

try:
    import shapefile  # pyshp
    
    shp_path = "/home/ga/gvsig_data/exports/african_cities.shp"
    
    if os.path.exists(shp_path):
        sf = shapefile.Reader(shp_path)
        
        # Check geometry type (1=Point, 3=PolyLine, 5=Polygon, etc.)
        shape_type = sf.shapeType
        if shape_type == 1 or shape_type == 11 or shape_type == 21: # Point, PointZ, PointM
            result["geometry_type"] = "Point"
        else:
            result["geometry_type"] = f"Type_{shape_type}"
            
        # Count features
        result["feature_count"] = len(sf)
        
        if result["feature_count"] > 0:
            result["valid_shapefile"] = True
            
            # Check Bounding Box
            # Africa approx: -26, -36 to 56, 38 (roughly)
            bbox = sf.bbox # [minx, miny, maxx, maxy]
            # Relaxed bounds check
            if bbox[0] >= -30 and bbox[1] >= -40 and bbox[2] <= 60 and bbox[3] <= 45:
                result["bbox_valid"] = True
            
            # Check attributes for City Names
            # Find index of NAME field
            fields = [f[0] for f in sf.fields[1:]] # skip DeletionFlag
            name_idx = -1
            for i, f_name in enumerate(fields):
                if "NAME" in f_name.upper():
                    name_idx = i
                    break
            
            if name_idx != -1:
                required = ["Cairo", "Lagos", "Kinshasa", "Nairobi", "Johannesburg", "Luanda", "Khartoum"]
                forbidden = ["Paris", "London", "New York", "Tokyo", "Beijing", "Moscow"]
                
                found_names = []
                
                for shape_rec in sf.iterShapeRecords():
                    rec = shape_rec.record
                    city_name = str(rec[name_idx])
                    found_names.append(city_name)
                    
                    if city_name in required and city_name not in result["cities_found"]:
                        result["cities_found"].append(city_name)
                    if city_name in forbidden and city_name not in result["cities_forbidden_found"]:
                        result["cities_forbidden_found"].append(city_name)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Run analysis
ANALYSIS_JSON="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    # Ensure pyshp is available (try installing again if missing, user might have reset env)
    pip3 install pyshp >/dev/null 2>&1 || true
    ANALYSIS_JSON=$(python3 /tmp/analyze_shapefile.py 2>/dev/null || echo "{}")
fi

# Check if app is running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE_BYTES,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": $ANALYSIS_JSON
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