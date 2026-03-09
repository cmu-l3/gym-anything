#!/bin/bash
echo "=== Exporting analyze_crop_health_ndvi_zonal_stats result ==="

source /workspace/scripts/task_utils.sh

# Define paths
NDVI_RASTER="/home/ga/GIS_Data/agriculture/ndvi_output.tif"
VECTOR_OUTPUT="/home/ga/GIS_Data/exports/fields_with_yield_potential.geojson"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check file existence and timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check Raster
RASTER_EXISTS="false"
RASTER_VALID="false"
RASTER_STATS="{}"

if [ -f "$NDVI_RASTER" ]; then
    RASTER_MTIME=$(stat -c %Y "$NDVI_RASTER" 2>/dev/null || echo "0")
    if [ "$RASTER_MTIME" -gt "$TASK_START" ]; then
        RASTER_EXISTS="true"
        # Validate Raster with Python (gdal)
        RASTER_STATS=$(python3 << 'PYEOF'
import json
import numpy as np
from osgeo import gdal

try:
    ds = gdal.Open("/home/ga/GIS_Data/agriculture/ndvi_output.tif")
    if ds is None:
        raise Exception("Cannot open raster")
    
    band = ds.GetRasterBand(1)
    arr = band.ReadAsArray()
    
    # Calculate basic stats
    min_val = float(np.min(arr))
    max_val = float(np.max(arr))
    mean_val = float(np.mean(arr))
    
    # Check if values look like NDVI (-1 to 1)
    valid_range = (min_val >= -1.1 and max_val <= 1.1)
    
    print(json.dumps({
        "valid": True,
        "valid_range": valid_range,
        "min": min_val,
        "max": max_val,
        "mean": mean_val
    }))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
        )
    fi
fi

# Check Vector
VECTOR_EXISTS="false"
VECTOR_STATS="{}"

if [ -f "$VECTOR_OUTPUT" ]; then
    VECTOR_MTIME=$(stat -c %Y "$VECTOR_OUTPUT" 2>/dev/null || echo "0")
    if [ "$VECTOR_MTIME" -gt "$TASK_START" ]; then
        VECTOR_EXISTS="true"
        # Validate Vector with Python
        VECTOR_STATS=$(python3 << 'PYEOF'
import json

try:
    with open("/home/ga/GIS_Data/exports/fields_with_yield_potential.geojson", 'r') as f:
        data = json.load(f)
    
    if data['type'] != 'FeatureCollection':
        raise Exception("Not a FeatureCollection")
        
    features = data['features']
    count = len(features)
    
    # Check attributes for "mean" or "ndvi"
    # Zonal stats might name field 'mean', '_mean', 'ndvi_mean', etc.
    found_mean_field = False
    field_name = ""
    extracted_means = {}
    
    if count > 0:
        props = features[0]['properties']
        keys = list(props.keys())
        # Look for keys containing 'mean' or 'ndvi' (case insensitive)
        candidates = [k for k in keys if 'mean' in k.lower() or 'ndvi' in k.lower()]
        
        # Filter out 'id', 'name', 'crop' if they accidentally match
        candidates = [k for k in candidates if k not in ['name', 'crop', 'id']]
        
        if candidates:
            found_mean_field = True
            field_name = candidates[0] # Take the best guess
            
            # Extract means for validation
            for feat in features:
                name = feat['properties'].get('name', 'Unknown')
                val = feat['properties'].get(field_name, None)
                if val is not None:
                    extracted_means[name] = float(val)

    print(json.dumps({
        "valid": True,
        "count": count,
        "has_mean_field": found_mean_field,
        "field_name": field_name,
        "values": extracted_means
    }))

except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
        )
    fi
fi

# Clean up QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# Write Result
cat > /tmp/task_result.json << EOF
{
    "raster_exists": $RASTER_EXISTS,
    "raster_stats": $RASTER_STATS,
    "vector_exists": $VECTOR_EXISTS,
    "vector_stats": $VECTOR_STATS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="