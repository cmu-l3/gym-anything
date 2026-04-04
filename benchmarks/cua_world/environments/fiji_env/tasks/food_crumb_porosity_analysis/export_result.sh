#!/bin/bash
echo "=== Exporting Food Crumb Porosity Analysis Results ==="

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
RESULTS_DIR="/home/ga/Fiji_Data/results/food_science"
CSV_FILE="$RESULTS_DIR/pore_measurements.csv"
REPORT_FILE="$RESULTS_DIR/quality_report.txt"
MASK_FILE="$RESULTS_DIR/segmentation_check.png"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to check file status
check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false" # Exists but old
        fi
    else
        echo "false"
    fi
}

CSV_CREATED=$(check_file "$CSV_FILE")
REPORT_CREATED=$(check_file "$REPORT_FILE")
MASK_CREATED=$(check_file "$MASK_FILE")

# Python script to parse the results locally and verify content
# We extract values here to pass to the verifier as JSON
PYTHON_PARSER=$(cat <<END_PYTHON
import csv
import re
import json
import os

results = {
    "csv_rows": 0,
    "mean_area": 0.0,
    "report_porosity": -1.0,
    "report_mean_area": -1.0
}

# Parse CSV
csv_path = "$CSV_FILE"
if os.path.exists(csv_path):
    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            areas = []
            for row in reader:
                # Flexible column name matching for 'Area'
                area_key = next((k for k in row.keys() if 'Area' in k), None)
                if area_key and row[area_key]:
                    try:
                        areas.append(float(row[area_key]))
                    except ValueError:
                        pass
            
            results["csv_rows"] = len(areas)
            if areas:
                results["mean_area"] = sum(areas) / len(areas)
    except Exception as e:
        results["csv_error"] = str(e)

# Parse Text Report
report_path = "$REPORT_FILE"
if os.path.exists(report_path):
    try:
        with open(report_path, 'r') as f:
            content = f.read()
            
            # Find numbers associated with Porosity or Void Fraction
            # Look for patterns like "Porosity: 45.2%" or "Void Fraction 0.45"
            porosity_match = re.search(r'(?i)(porosity|void\s*fraction).*?([0-9]+(\.[0-9]+)?)', content)
            if porosity_match:
                val = float(porosity_match.group(2))
                # Normalize if < 1.0 (e.g. 0.45 -> 45.0) unless it's clearly meant to be small
                if val < 1.0 and "fraction" in porosity_match.group(1).lower():
                     val = val * 100
                results["report_porosity"] = val
            
            # Find Mean Pore Area
            area_match = re.search(r'(?i)(mean|average).*?area.*?([0-9]+(\.[0-9]+)?)', content)
            if area_match:
                results["report_mean_area"] = float(area_match.group(2))
                
    except Exception as e:
        results["report_error"] = str(e)

print(json.dumps(results))
END_PYTHON
)

# Run parser
PARSED_DATA=$(python3 -c "$PYTHON_PARSER")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_created": $CSV_CREATED,
    "report_created": $REPORT_CREATED,
    "mask_created": $MASK_CREATED,
    "parsed_data": $PARSED_DATA
}
EOF

# Move to final location
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="