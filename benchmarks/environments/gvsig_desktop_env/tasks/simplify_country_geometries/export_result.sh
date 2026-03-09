#!/bin/bash
echo "=== Exporting simplify_country_geometries results ==="

source /workspace/scripts/task_utils.sh

# Paths
INPUT_SHP="/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp"
OUTPUT_SHP="/home/ga/gvsig_data/exports/countries_simplified.shp"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END_TIME=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Install pyshp for analysis (lightweight python shapefile library)
# We do this in export script to avoid bloating the base image if not needed elsewhere
if ! python3 -c "import shapefile" 2>/dev/null; then
    echo "Installing pyshp for verification analysis..."
    pip3 install --no-cache-dir pyshp >/dev/null 2>&1
fi

# Create a Python script to analyze the shapefiles
cat > /tmp/analyze_shapefiles.py << PYEOF
import sys
import os
import json
import shapefile
import time

input_path = "$INPUT_SHP"
output_path = "$OUTPUT_SHP"
task_start = $TASK_START_TIME

result = {
    "input_exists": False,
    "output_exists": False,
    "input_features": 0,
    "output_features": 0,
    "input_vertices": 0,
    "output_vertices": 0,
    "output_created_during_task": False,
    "geometry_type_match": False,
    "valid_geometry": True,
    "error": None
}

try:
    # Analyze Input
    if os.path.exists(input_path):
        result["input_exists"] = True
        with shapefile.Reader(input_path) as sf:
            result["input_features"] = len(sf)
            # Sum all points in all shapes
            result["input_vertices"] = sum(len(s.points) for s in sf.shapes())

    # Analyze Output
    if os.path.exists(output_path):
        result["output_exists"] = True
        
        # Check timestamp
        mtime = os.path.getmtime(output_path)
        if mtime > task_start:
            result["output_created_during_task"] = True
            
        try:
            with shapefile.Reader(output_path) as sf:
                result["output_features"] = len(sf)
                result["output_vertices"] = sum(len(s.points) for s in sf.shapes())
                
                # Check geometry type (5 is Polygon)
                # We expect Polygon (5) or Null (0) if simplified to nothing, 
                # but input is Polygon.
                result["geometry_type_match"] = (sf.shapeType == 5)
                
                # Basic check for empty geometries
                for s in sf.shapes():
                    if len(s.points) < 3 and len(s.points) > 0:
                        # Technically a polygon needs 3 points, but null shapes have 0
                        # This is just a sanity check
                        pass
                        
        except Exception as e:
            result["valid_geometry"] = False
            result["error"] = f"Reading output failed: {str(e)}"

except Exception as e:
    result["error"] = str(e)

# Calculate reduction percentage
if result["input_vertices"] > 0:
    result["reduction_percent"] = (1 - (result["output_vertices"] / result["input_vertices"])) * 100
else:
    result["reduction_percent"] = 0

print(json.dumps(result, indent=2))
PYEOF

# Run analysis and save to JSON
python3 /tmp/analyze_shapefiles.py > /tmp/task_analysis.json 2>/dev/null || echo '{"error": "Analysis script failed"}' > /tmp/task_analysis.json

# Merge screenshot path and app status into result
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# Create final JSON structure
cat > /tmp/task_result.json << EOF
{
    "analysis": $(cat /tmp/task_analysis.json),
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions for easy reading by copy_from_env
chmod 644 /tmp/task_result.json

echo "Result analysis:"
cat /tmp/task_result.json

echo "=== Export complete ==="