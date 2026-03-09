#!/bin/bash
echo "=== Exporting classify_populated_places result ==="

source /workspace/scripts/task_utils.sh

# Paths
SHP_PATH="/home/ga/gvsig_data/cities/ne_110m_populated_places.shp"
DBF_PATH="/home/ga/gvsig_data/cities/ne_110m_populated_places.dbf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file modification
FILE_MODIFIED="false"
if [ -f "$DBF_PATH" ]; then
    DBF_MTIME=$(stat -c %Y "$DBF_PATH" 2>/dev/null || echo "0")
    if [ "$DBF_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Run python verification script INSIDE the container to analyze the DBF
# We do this here because the host might not have pyshp, but we installed it in setup_task.sh
echo "Running internal verification script..."

cat > /tmp/verify_dbf.py << 'PYEOF'
import shapefile
import json
import sys
import os

dbf_path = "/home/ga/gvsig_data/cities/ne_110m_populated_places.dbf"
result = {
    "field_exists": False,
    "megacity_count": 0,
    "megacity_correct": 0,
    "city_count": 0,
    "city_correct": 0,
    "total_records": 0,
    "error": None
}

try:
    sf = shapefile.Reader(dbf_path)
    fields = [f[0] for f in sf.fields[1:]]  # Skip deletion flag
    records = sf.records()
    result["total_records"] = len(records)
    
    # Check if URBAN_CAT exists (case insensitive)
    target_field = "URBAN_CAT"
    field_idx = -1
    for i, f in enumerate(fields):
        if f.upper() == target_field:
            field_idx = i
            result["field_exists"] = True
            break
            
    # Find POP_MAX field
    pop_idx = -1
    for i, f in enumerate(fields):
        if f.upper() == "POP_MAX":
            pop_idx = i
            break
            
    if result["field_exists"] and pop_idx != -1:
        for r in records:
            pop = r[pop_idx]
            cat = str(r[field_idx]).strip()
            
            # Logic check
            if pop >= 10000000:
                result["megacity_count"] += 1
                if cat == "Megacity":
                    result["megacity_correct"] += 1
            else:
                result["city_count"] += 1
                if cat == "City":
                    result["city_correct"] += 1

except Exception as e:
    result["error"] = str(e)

with open("/tmp/dbf_analysis.json", "w") as f:
    json.dump(result, f)
PYEOF

# Execute the python script
python3 /tmp/verify_dbf.py || echo '{"error": "Failed to run verification script"}' > /tmp/dbf_analysis.json

# Combine results into final JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_modified": $FILE_MODIFIED,
    "screenshot_path": "/tmp/task_final.png",
    "dbf_analysis": $(cat /tmp/dbf_analysis.json)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json