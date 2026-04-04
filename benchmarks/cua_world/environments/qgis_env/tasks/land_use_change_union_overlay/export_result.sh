#!/bin/bash
echo "=== Exporting land_use_change_union_overlay result ==="

source /workspace/scripts/task_utils.sh

# Fallback utils
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Check Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_PATH="/home/ga/GIS_Data/exports/change_matrix.csv"

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$EXPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPORT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze CSV Content with Python
# We need to verify that:
# - Headers include class fields from both 2015 and 2025
# - An area field exists
# - The sums of areas for specific transitions are correct
ANALYSIS_JSON=$(python3 << 'PYEOF'
import csv
import json
import sys

csv_path = "/home/ga/GIS_Data/exports/change_matrix.csv"

result = {
    "valid_csv": False,
    "headers": [],
    "has_class_2015": False,
    "has_class_2025": False,
    "has_area_field": False,
    "sum_forest_urban": 0.0,
    "sum_forest_forest": 0.0,
    "sum_farm_farm": 0.0,
    "total_area": 0.0,
    "row_count": 0
}

try:
    with open(csv_path, 'r', encoding='utf-8') as f:
        # Sniff delimiter to handle potential semi-colon csvs
        sample = f.read(1024)
        f.seek(0)
        sniffer = csv.Sniffer()
        try:
            dialect = sniffer.sniff(sample)
        except csv.Error:
            dialect = 'excel'
            
        reader = csv.DictReader(f, dialect=dialect)
        
        # Check headers
        headers = [h.lower().strip() for h in reader.fieldnames] if reader.fieldnames else []
        result["headers"] = headers
        result["valid_csv"] = True
        
        # Identify critical columns
        col_2015 = next((h for h in headers if "class" in h and "2015" in h), None)
        col_2025 = next((h for h in headers if "class" in h and "2025" in h), None)
        col_area = next((h for h in headers if "area" in h or "sqkm" in h), None)
        
        result["has_class_2015"] = bool(col_2015)
        result["has_class_2025"] = bool(col_2025)
        result["has_area_field"] = bool(col_area)
        
        # Sum areas
        for row in reader:
            result["row_count"] += 1
            if col_area and col_2015 and col_2025:
                try:
                    # Handle keys carefully as DictReader keys match original case
                    # We map back to original keys found in fieldnames
                    orig_col_2015 = [k for k in reader.fieldnames if k.lower().strip() == col_2015][0]
                    orig_col_2025 = [k for k in reader.fieldnames if k.lower().strip() == col_2025][0]
                    orig_col_area = [k for k in reader.fieldnames if k.lower().strip() == col_area][0]
                    
                    val_2015 = row[orig_col_2015].lower()
                    val_2025 = row[orig_col_2025].lower()
                    area = float(row[orig_col_area])
                    
                    result["total_area"] += area
                    
                    if "forest" in val_2015 and "urban" in val_2025:
                        result["sum_forest_urban"] += area
                    elif "forest" in val_2015 and "forest" in val_2025:
                        result["sum_forest_forest"] += area
                    elif "farm" in val_2015 and "farm" in val_2025:
                        result["sum_farm_farm"] += area
                        
                except (ValueError, KeyError, IndexError):
                    continue

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Check Application State
APP_RUNNING="false"
if is_qgis_running; then
    APP_RUNNING="true"
    # Clean up QGIS
    kill_qgis ga 2>/dev/null || true
fi

# 5. Compile Result JSON
# Use a temp file to avoid permission issues when creating the final result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "csv_analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="