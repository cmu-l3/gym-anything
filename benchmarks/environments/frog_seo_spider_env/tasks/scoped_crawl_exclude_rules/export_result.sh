#!/bin/bash
# Export script for Scoped Crawl Exclude Rules task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Scoped Crawl Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Initialize result variables
LATEST_CSV=""
FILE_CREATED="false"
TOTAL_ROWS=0
CATEGORY_URLS_COUNT=0
CATALOGUE_URLS_COUNT=0
TARGET_DOMAIN_COUNT=0
HAS_STANDARD_COLS="false"
SF_RUNNING="false"
WINDOW_INFO=""

# Check if SF is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Get window title
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# Find the most recently modified CSV in the export directory
if [ -d "$EXPORT_DIR" ]; then
    # Find files modified after task start
    NEWEST_FILE=$(find "$EXPORT_DIR" -name "*.csv" -newermt "@$TASK_START_EPOCH" -type f -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -n "$NEWEST_FILE" ]; then
        LATEST_CSV="$NEWEST_FILE"
        FILE_CREATED="true"
        echo "Found new export file: $LATEST_CSV"
        
        # Parse the CSV using Python for reliability
        python3 << PYEOF
import csv
import json
import sys

csv_path = "$LATEST_CSV"
result = {
    "total_rows": 0,
    "category_count": 0,
    "catalogue_count": 0,
    "target_domain_count": 0,
    "has_standard_cols": False,
    "columns": []
}

try:
    with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
        # Skip first few lines if they are not headers (SF sometimes adds report metadata)
        # We'll try to find the header line
        content = f.readlines()
        header_row_idx = 0
        for i, line in enumerate(content[:5]):
            if "Address" in line or "URL" in line and "Status Code" in line:
                header_row_idx = i
                break
        
        # Reset file pointer or just use content
        reader = csv.DictReader(content[header_row_idx:])
        result["columns"] = reader.fieldnames if reader.fieldnames else []
        
        # Check standard columns
        required = ["Address", "Status Code", "Title 1"]
        if reader.fieldnames and all(any(req in col for col in reader.fieldnames) for req in required):
            result["has_standard_cols"] = True
            
        # Identify Address column
        addr_col = next((c for c in reader.fieldnames if "Address" in c or "URL" in c), None)
        
        if addr_col:
            for row in reader:
                url = row.get(addr_col, "")
                if url:
                    result["total_rows"] += 1
                    if "books.toscrape.com" in url:
                        result["target_domain_count"] += 1
                    if "/category/" in url:
                        result["category_count"] += 1
                    if "/catalogue/" in url:
                        result["catalogue_count"] += 1

except Exception as e:
    result["error"] = str(e)

with open('/tmp/csv_analysis.json', 'w') as f:
    json.dump(result, f)
PYEOF

        # Read back the python analysis
        if [ -f "/tmp/csv_analysis.json" ]; then
            TOTAL_ROWS=$(python3 -c "import json; print(json.load(open('/tmp/csv_analysis.json')).get('total_rows', 0))")
            CATEGORY_URLS_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/csv_analysis.json')).get('category_count', 0))")
            CATALOGUE_URLS_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/csv_analysis.json')).get('catalogue_count', 0))")
            TARGET_DOMAIN_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/csv_analysis.json')).get('target_domain_count', 0))")
            HAS_STANDARD_COLS=$(python3 -c "import json; print(str(json.load(open('/tmp/csv_analysis.json')).get('has_standard_cols', False)).lower())")
        fi
    fi
fi

# Write final result JSON
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "file_created": "$FILE_CREATED" == "true",
    "latest_csv_path": "$LATEST_CSV",
    "total_rows": int("$TOTAL_ROWS"),
    "category_urls_count": int("$CATEGORY_URLS_COUNT"),
    "catalogue_urls_count": int("$CATALOGUE_URLS_COUNT"),
    "target_domain_count": int("$TARGET_DOMAIN_COUNT"),
    "has_standard_cols": "$HAS_STANDARD_COLS" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="