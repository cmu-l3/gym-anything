#!/bin/bash
echo "=== Exporting convert_reproject_gps_gpx result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Gather Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/GIS_Data/exports/field_observations.gpkg"

# 3. Analyze Output File using Python
# We use python3 with geopandas/fiona to inspect the GeoPackage content
# This is much more reliable than file size checks
python3 << 'PYEOF' > /tmp/analysis_result.json
import json
import os
import sys
import time

output_path = "/home/ga/GIS_Data/exports/field_observations.gpkg"
task_start = int(os.environ.get('TASK_START', 0))

result = {
    "exists": False,
    "valid_format": False,
    "crs": None,
    "crs_is_metric": False,
    "geometry_type": None,
    "feature_count": 0,
    "layer_names": [],
    "created_during_task": False,
    "file_size": 0,
    "error": None
}

try:
    if os.path.exists(output_path):
        result["exists"] = True
        result["file_size"] = os.path.getsize(output_path)
        mtime = os.path.getmtime(output_path)
        
        # Check timestamp (allow 5s buffer for clock skew)
        if mtime >= (task_start - 5):
            result["created_during_task"] = True
            
        # Analyze content using fiona (standard GIS IO library)
        import fiona
        
        try:
            layers = fiona.listlayers(output_path)
            result["layer_names"] = layers
            result["valid_format"] = True
            
            if len(layers) > 0:
                # Open the first layer (usually the one exported)
                with fiona.open(output_path, layer=layers[0]) as src:
                    # Get CRS
                    crs = src.crs
                    result["crs"] = str(crs)
                    
                    # Check if CRS is Pseudo-Mercator (EPSG:3857)
                    # EPSG:3857 usually has units=m and is projected
                    if 'init' in crs and 'epsg:3857' in str(crs['init']).lower():
                        result["crs_is_metric"] = True
                    elif 'units' in crs and crs['units'] == 'm':
                        result["crs_is_metric"] = True
                    # Check EPSG code specifically if available
                    if src.crs_wkt and '3857' in src.crs_wkt:
                        result["crs_is_metric"] = True

                    # Get Geometry Type
                    result["geometry_type"] = src.schema['geometry']
                    
                    # Get Count
                    result["feature_count"] = len(src)
                    
        except Exception as e:
            result["error"] = f"Fiona error: {str(e)}"
            # Fallback if fiona fails but file exists (e.g. locked)
            pass

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 4. Construct Final JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "analysis": $(cat /tmp/analysis_result.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="