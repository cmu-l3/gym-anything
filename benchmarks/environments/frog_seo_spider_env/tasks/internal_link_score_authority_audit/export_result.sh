#!/bin/bash
# Export script for Internal Link Score Authority Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting Internal Link Score Result ==="

# Trap errors
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Define Paths and Variables
EXPORT_PATH="/home/ga/Documents/SEO/exports/authority_audit.csv"
REPORT_PATH="/home/ga/Documents/SEO/reports/top_authority_pages.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

CSV_EXISTS="false"
CSV_MODIFIED_DURING_TASK="false"
HAS_LINK_SCORE_COL="false"
MAX_LINK_SCORE=0
ROW_COUNT=0
REPORT_EXISTS="false"
REPORT_CONTENT=""
SF_RUNNING="false"

# 3. Check Application State
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 4. Analyze CSV Export
if [ -f "$EXPORT_PATH" ]; then
    CSV_EXISTS="true"
    
    # Check modification time
    FILE_EPOCH=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_MODIFIED_DURING_TASK="true"
        
        # Use Python to parse CSV safely (handle quoting/commas)
        # We need to check if "Link Score" exists and if it has values > 0
        python3 << PYEOF
import csv
import sys
import json

csv_path = "$EXPORT_PATH"
has_col = False
max_score = 0.0
rows = 0

try:
    with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
        # Skip first line if it's the specific SF export header "Internal - All" etc, 
        # but usually standard exports have headers on line 1 or 2.
        # SF exports often have a metadata line first. Let's peek.
        pos = f.tell()
        first_line = f.readline()
        f.seek(pos)
        
        # Standard csv reader
        reader = csv.DictReader(f)
        
        # Handle potential "Screaming Frog SEO Spider..." first line header by retrying
        if reader.fieldnames and "Address" not in reader.fieldnames and "Link Score" not in reader.fieldnames:
             f.seek(pos)
             f.readline() # skip potential metadata line
             reader = csv.DictReader(f)
        
        if reader.fieldnames:
            # Check for column variations
            keys = reader.fieldnames
            ls_key = next((k for k in keys if "Link Score" in k), None)
            
            if ls_key:
                has_col = True
                for row in reader:
                    rows += 1
                    try:
                        val = float(row[ls_key])
                        if val > max_score:
                            max_score = val
                    except ValueError:
                        pass
except Exception as e:
    print(f"Error parsing CSV: {e}", file=sys.stderr)

# Output results to a temporary JSON fragment
result = {
    "has_link_score_col": has_col,
    "max_link_score": max_score,
    "row_count": rows
}
with open('/tmp/csv_analysis.json', 'w') as f:
    json.dump(result, f)
PYEOF

        # Read back the python analysis
        if [ -f /tmp/csv_analysis.json ]; then
            HAS_LINK_SCORE_COL=$(python3 -c "import json; print(str(json.load(open('/tmp/csv_analysis.json'))['has_link_score_col']).lower())")
            MAX_LINK_SCORE=$(python3 -c "import json; print(json.load(open('/tmp/csv_analysis.json'))['max_link_score'])")
            ROW_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/csv_analysis.json'))['row_count'])")
        fi
    fi
fi

# 5. Analyze Text Report
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000) # Get first 1KB
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sf_running": $SF_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_modified_during_task": $CSV_MODIFIED_DURING_TASK,
    "has_link_score_col": $HAS_LINK_SCORE_COL,
    "max_link_score": $MAX_LINK_SCORE,
    "row_count": $ROW_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R .),
    "timestamp": "$(date -Iseconds)"
}
EOF

# 7. Finalize Result File
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="