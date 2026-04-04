#!/bin/bash
echo "=== Exporting Field Calculator Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_CSV="$EXPORT_DIR/countries_gdp_per_capita.csv"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find the CSV file (allow flexibility in naming if it contains 'gdp')
FOUND_CSV=""
if [ -f "$EXPECTED_CSV" ]; then
    FOUND_CSV="$EXPECTED_CSV"
else
    # Find newest CSV containing 'gdp' or 'capita' or just any csv created recently
    POTENTIAL=$(find "$EXPORT_DIR" -name "*.csv" -mmin -10 2>/dev/null | head -1)
    if [ -n "$POTENTIAL" ]; then
        FOUND_CSV="$POTENTIAL"
    fi
fi

# Initialize JSON output
cat > /tmp/analysis_script.py << 'PYEOF'
import csv
import json
import sys
import os
import time

csv_path = sys.argv[1]
task_start = int(sys.argv[2])

result = {
    "file_exists": False,
    "file_path": csv_path,
    "created_during_task": False,
    "is_valid_csv": False,
    "row_count": 0,
    "headers": [],
    "has_gdp_field": False,
    "numeric_values_count": 0,
    "plausible_values_count": 0,
    "distinct_values_count": 0,
    "sample_values": []
}

if not csv_path or not os.path.exists(csv_path):
    print(json.dumps(result))
    sys.exit(0)

result["file_exists"] = True
mtime = os.path.getmtime(csv_path)
if mtime > task_start:
    result["created_during_task"] = True

try:
    with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
        # Sniff delimiter
        sample = f.read(1024)
        f.seek(0)
        sniffer = csv.Sniffer()
        try:
            dialect = sniffer.sniff(sample)
        except csv.Error:
            dialect = None
        
        if dialect:
            reader = csv.DictReader(f, dialect=dialect)
        else:
            # Fallback to standard comma
            reader = csv.DictReader(f)
            
        result["headers"] = reader.fieldnames if reader.fieldnames else []
        
        # Check for GDP field (flexible matching)
        gdp_field = None
        for h in result["headers"]:
            clean_h = h.lower().replace("_", "").replace(" ", "")
            if "gdppercapita" in clean_h or "gdpcapita" in clean_h or ("gdp" in clean_h and "pc" in clean_h):
                gdp_field = h
                result["has_gdp_field"] = True
                break
        
        rows = list(reader)
        result["row_count"] = len(rows)
        result["is_valid_csv"] = True
        
        if gdp_field:
            values = []
            for row in rows:
                val = row.get(gdp_field, "")
                try:
                    # Handle potential string formatting issues
                    val_float = float(str(val).replace(",", ""))
                    values.append(val_float)
                except ValueError:
                    continue
            
            result["numeric_values_count"] = len(values)
            result["distinct_values_count"] = len(set(values))
            
            # Check plausibility (100 < GDP < 200,000 typically)
            plausible = [v for v in values if 100 <= v <= 200000]
            result["plausible_values_count"] = len(plausible)
            result["sample_values"] = values[:5]

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Run analysis
if [ -n "$FOUND_CSV" ]; then
    python3 /tmp/analysis_script.py "$FOUND_CSV" "$TASK_START" > /tmp/task_result.json
else
    echo '{"file_exists": false}' > /tmp/task_result.json
fi

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Analysis complete. Result:"
cat /tmp/task_result.json