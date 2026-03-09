#!/bin/bash
echo "=== Exporting calculate_city_density_on_grid results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state
take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Define expected output
OUTPUT_SHP="/home/ga/gvsig_data/exports/city_density_grid.shp"

# 3. Analyze Output (Inside container to avoid dependency issues on host)
# We install pyshp locally to analyze the shapefile content
echo "Installing pyshp for analysis..."
pip3 install pyshp > /dev/null 2>&1 || true

# Python script to analyze the shapefile
cat > /tmp/analyze_output.py << PYEOF
import json
import sys
import os
import time

result = {
    "exists": False,
    "created_during_task": False,
    "geometry_type": "Unknown",
    "feature_count": 0,
    "fields": [],
    "max_count_value": 0,
    "sum_count_value": 0,
    "has_count_field": False,
    "error": ""
}

shp_path = "$OUTPUT_SHP"
task_start = $TASK_START

try:
    if os.path.exists(shp_path):
        result["exists"] = True
        
        # Check modification time
        mtime = os.path.getmtime(shp_path)
        if mtime > task_start:
            result["created_during_task"] = True
            
        try:
            import shapefile
            sf = shapefile.Reader(shp_path)
            
            # Geometry Type (5=Polygon)
            result["geometry_type"] = sf.shapeType
            result["feature_count"] = len(sf)
            
            # Analyze fields
            fields = [f[0] for f in sf.fields[1:]] # Skip deletion flag
            result["fields"] = fields
            
            # Find count field and calculate stats
            # We look for numeric fields and sum them up
            max_sum = 0
            best_field = ""
            
            # Iterate through records to find numeric data
            # Note: This might be slow for huge files, but our grid is small (~162 features)
            records = sf.records()
            
            for i, field in enumerate(fields):
                try:
                    # Get values for this column
                    values = [r[i] for r in records]
                    # Check if numeric
                    if all(isinstance(v, (int, float)) for v in values):
                        col_sum = sum(values)
                        col_max = max(values) if values else 0
                        
                        # Heuristic: A count field for cities should sum to approx 243
                        # Area fields or ID fields might behave differently
                        if col_sum > 0:
                            if col_sum > max_sum:
                                max_sum = col_sum
                                result["sum_count_value"] = col_sum
                                result["max_count_value"] = col_max
                except Exception:
                    continue

            if result["sum_count_value"] > 0:
                result["has_count_field"] = True
                
        except ImportError:
            result["error"] = "pyshp not installed"
        except Exception as e:
            result["error"] = str(e)
            
except Exception as e:
    result["error"] = f"General error: {str(e)}"

print(json.dumps(result))
PYEOF

# Run analysis
echo "Analyzing shapefile..."
ANALYSIS_JSON=$(python3 /tmp/analyze_output.py)
echo "Analysis result: $ANALYSIS_JSON"

# 4. Check if gvSIG is still running
APP_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": $ANALYSIS_JSON
}
EOF

# 6. Save result to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON" /tmp/analyze_output.py

echo "=== Export complete ==="