#!/bin/bash
echo "=== Exporting compute_country_centroids result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final visual state
take_screenshot /tmp/task_final.png

# 2. Gather timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_SHP="/home/ga/gvsig_data/exports/country_centroids.shp"

# 3. Analyze the output Shapefile using Python (pyshp)
# We run this INSIDE the container to generate a detailed JSON report
# This avoids needing complex GIS libraries on the verifier host
echo "Analyzing shapefile geometry and attributes..."

python3 << EOF > /tmp/shapefile_analysis.json
import json
import os
import time
import sys

# Default result structure
result = {
    "file_exists": False,
    "file_fresh": False,
    "shape_type": None,
    "feature_count": 0,
    "valid_coords": True,
    "bbox": None,
    "fields": [],
    "error": None
}

shp_path = "$OUTPUT_SHP"
task_start = $TASK_START

try:
    if os.path.exists(shp_path):
        result["file_exists"] = True
        
        # Check timestamp (anti-gaming)
        mtime = os.path.getmtime(shp_path)
        if mtime > task_start:
            result["file_fresh"] = True
            
        try:
            import shapefile
            
            # Read shapefile
            sf = shapefile.Reader(shp_path)
            
            # 1. Geometry Type (1=Point, 3=PolyLine, 5=Polygon, etc.)
            result["shape_type"] = sf.shapeType
            
            # 2. Feature Count
            result["feature_count"] = len(sf)
            
            # 3. Attributes
            # fields is list of (name, type, length, decimals)
            # Skip deletion flag field (first one)
            result["fields"] = [f[0] for f in sf.fields[1:]]
            
            # 4. Coordinate Validity check (sample first 20 points)
            valid = True
            shapes = sf.shapes()
            if shapes:
                result["bbox"] = sf.bbox
                for i, shp in enumerate(shapes[:20]):
                    if not shp.points: continue
                    x, y = shp.points[0]
                    # Check for valid lat/lon ranges roughly
                    if not (-180 <= x <= 180 and -90 <= y <= 90):
                        valid = False
                        break
            result["valid_coords"] = valid
            
        except ImportError:
            result["error"] = "pyshp not installed"
        except Exception as e:
            result["error"] = str(e)
            
except Exception as e:
    result["error"] = f"General error: {str(e)}"

print(json.dumps(result))
EOF

# 4. Check if gvSIG was still running
APP_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create Final Result JSON
# Combine the python analysis with bash-level checks
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "analysis": $(cat /tmp/shapefile_analysis.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions for copy_from_env
chmod 644 /tmp/task_result.json

echo "Result summary:"
cat /tmp/task_result.json
echo "=== Export complete ==="