#!/bin/bash
echo "=== Exporting annotate_wells_with_elevation result ==="

source /workspace/scripts/task_utils.sh

# Output path
OUTPUT_PATH="/home/ga/GIS_Data/exports/wells_with_elevation.geojson"
RASTER_PATH="/home/ga/GIS_Data/rasters/SRTM_Elevation.tif"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if output exists
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Verify Data Content (Python)
echo "Running verification script..."
cat > /tmp/verify_data.py << 'PYEOF'
import json
import sys
import os
from osgeo import gdal, osr

output_path = sys.argv[1]
raster_path = sys.argv[2]

result = {
    "valid_geojson": False,
    "feature_count": 0,
    "has_elevation_field": False,
    "accuracy_score": 0.0,
    "avg_error": 9999.0
}

if not os.path.exists(output_path):
    print(json.dumps(result))
    sys.exit(0)

try:
    # Load Raster
    ds = gdal.Open(raster_path)
    gt = ds.GetGeoTransform()
    band = ds.GetRasterBand(1)
    nodata = band.GetNoDataValue()

    def get_val(lon, lat):
        px = int((lon - gt[0]) / gt[1])
        py = int((lat - gt[3]) / gt[5])
        try:
            val = band.ReadAsArray(px, py, 1, 1)[0][0]
            if val == nodata: return None
            return float(val)
        except:
            return None

    # Load Vector
    with open(output_path) as f:
        data = json.load(f)
    
    result["valid_geojson"] = True
    features = data.get("features", [])
    result["feature_count"] = len(features)
    
    if not features:
        print(json.dumps(result))
        sys.exit(0)

    # Check for elevation field
    # Agent might name it "elevation", "elevation_1", "SAMPLE_1", etc.
    # We look for any numeric field that wasn't in the original (id, well_name)
    sample_props = features[0]["properties"]
    elev_field = None
    
    # Heuristic: look for field containing 'elev' or 'band' or 'value', or just any new float field
    # But description specifically asked for prefix 'elevation'
    candidates = [k for k in sample_props.keys() if k not in ["id", "well_name"]]
    
    for c in candidates:
        if isinstance(sample_props[c], (int, float)):
            elev_field = c
            break
            
    if elev_field:
        result["has_elevation_field"] = True
        
        # Calculate Accuracy
        total_error = 0
        valid_samples = 0
        
        for feat in features:
            coords = feat["geometry"]["coordinates"]
            agent_val = feat["properties"].get(elev_field)
            
            # Ground truth
            gt_val = get_val(coords[0], coords[1])
            
            if gt_val is not None and agent_val is not None:
                diff = abs(float(agent_val) - gt_val)
                total_error += diff
                valid_samples += 1
        
        if valid_samples > 0:
            result["avg_error"] = total_error / valid_samples
            # Score: 100 if error is negligible (floating point diff), decay otherwise
            # QGIS sampling is usually exact nearest neighbor or interpolation. 
            # Even with interpolation, it should be close.
            # We assume Nearest Neighbor default or Bilinear, error should be low.
            if result["avg_error"] < 0.1:
                result["accuracy_score"] = 100.0
            elif result["avg_error"] < 1.0:
                result["accuracy_score"] = 90.0
            elif result["avg_error"] < 10.0:
                result["accuracy_score"] = 50.0
            else:
                result["accuracy_score"] = 0.0
                
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

VERIFICATION_JSON=$(python3 /tmp/verify_data.py "$OUTPUT_PATH" "$RASTER_PATH")

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "verification_analysis": $VERIFICATION_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe copy to avoid permission issues
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="