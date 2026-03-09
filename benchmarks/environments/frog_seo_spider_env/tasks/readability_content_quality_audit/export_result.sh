#!/bin/bash
# Export script for Readability Content Quality Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Readability Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
EXPECTED_CSV="$EXPORT_DIR/readability_audit.csv"
EXPECTED_REPORT="$REPORTS_DIR/hardest_to_read.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

CSV_EXISTS="false"
CSV_MODIFIED_DURING_TASK="false"
HAS_READABILITY_COLUMN="false"
HAS_DATA_ROWS="false"
ROW_COUNT=0
TARGET_DOMAIN_FOUND="false"

REPORT_EXISTS="false"
REPORT_HAS_URL="false"
REPORT_CONTENT=""

SF_RUNNING="false"

# Check if SF is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Check CSV file
if [ -f "$EXPECTED_CSV" ]; then
    CSV_EXISTS="true"
    
    # Check timestamp
    FILE_EPOCH=$(stat -c %Y "$EXPECTED_CSV" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_MODIFIED_DURING_TASK="true"
        
        # Parse CSV content using Python for reliability
        # We need to check for "Flesch Reading Ease" or similar header
        # And check if rows contain books.toscrape.com
        
        python3 << PYEOF
import csv
import json
import sys

csv_path = "$EXPECTED_CSV"
result = {
    "has_readability": False,
    "has_data": False,
    "row_count": 0,
    "domain_found": False
}

try:
    with open(csv_path, 'r', encoding='utf-8', errors='ignore') as f:
        # Read first few lines to handle potential BOM or weird formatting
        start_pos = f.tell()
        line = f.readline()
        f.seek(start_pos)
        
        reader = csv.reader(f)
        headers = next(reader, [])
        
        # Check headers for Readability/Flesch
        # SF column names: "Flesch Reading Ease", "Flesch-Kincaid Grade Level"
        header_str = " ".join(headers).lower()
        if "flesch" in header_str or "readability" in header_str:
            result["has_readability"] = True
            
        rows = list(reader)
        result["row_count"] = len(rows)
        
        if len(rows) > 0:
            result["has_data"] = True
            
            # Check for domain in first column (Address) or any column
            sample_str = " ".join(rows[0]).lower()
            if "books.toscrape.com" in sample_str:
                result["domain_found"] = True
            else:
                # Check first 5 rows just in case
                for r in rows[:5]:
                    if "books.toscrape.com" in " ".join(r).lower():
                        result["domain_found"] = True
                        break

except Exception as e:
    print(f"Error parsing CSV: {e}", file=sys.stderr)

with open('/tmp/csv_analysis.json', 'w') as f:
    json.dump(result, f)
PYEOF

        # Load results from python script
        if [ -f "/tmp/csv_analysis.json" ]; then
            HAS_READABILITY_COLUMN=$(python3 -c "import json; print(str(json.load(open('/tmp/csv_analysis.json'))['has_readability']).lower())")
            HAS_DATA_ROWS=$(python3 -c "import json; print(str(json.load(open('/tmp/csv_analysis.json'))['has_data']).lower())")
            ROW_COUNT=$(python3 -c "import json; print(int(json.load(open('/tmp/csv_analysis.json'))['row_count']))")
            TARGET_DOMAIN_FOUND=$(python3 -c "import json; print(str(json.load(open('/tmp/csv_analysis.json'))['domain_found']).lower())")
        fi
    fi
fi

# Check Report file
if [ -f "$EXPECTED_REPORT" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$EXPECTED_REPORT" | head -n 1) # Read first line
    
    # Check if content looks like a URL
    if echo "$REPORT_CONTENT" | grep -qi "http"; then
        REPORT_HAS_URL="true"
    fi
fi

# Get Window Info for debugging
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# Create JSON result
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "csv_exists": "$CSV_EXISTS" == "true",
    "csv_modified": "$CSV_MODIFIED_DURING_TASK" == "true",
    "has_readability_column": "$HAS_READABILITY_COLUMN" == "true",
    "has_data_rows": "$HAS_DATA_ROWS" == "true",
    "row_count": $ROW_COUNT,
    "target_domain_found": "$TARGET_DOMAIN_FOUND" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_has_url": "$REPORT_HAS_URL" == "true",
    "window_info": """$WINDOW_INFO""",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

cat /tmp/task_result.json

echo "=== Export Complete ==="