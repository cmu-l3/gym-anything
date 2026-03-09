#!/bin/bash
# Export script for chinook_revenue_quintile_analysis

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

CSV_PATH="/home/ga/Documents/exports/revenue_quintiles.csv"
SQL_PATH="/home/ga/Documents/scripts/quintile_analysis.sql"
GT_FILE="/tmp/quintile_gt.json"

# Take final screenshot
take_screenshot /tmp/task_end.png
sleep 1

# 1. Analyze CSV Output
CSV_EXISTS="false"
CSV_VALID="false"
ROW_COUNT=0
Q1_REVENUE=0
Q5_REVENUE=0
MONOTONIC="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Count data rows (subtract header)
    TOTAL_LINES=$(wc -l < "$CSV_PATH")
    ROW_COUNT=$((TOTAL_LINES - 1))
    
    # Python script to parse CSV content
    # Extracts Q1 and Q5 revenue and checks basic structure
    read -r CSV_JSON << PYEOF
$(python3 -c "
import csv
import json
import sys

try:
    rows = []
    with open('$CSV_PATH', 'r') as f:
        reader = csv.DictReader(f)
        # Normalize headers to lower case
        headers = [h.lower() for h in (reader.fieldnames or [])]
        
        # Identify revenue column
        rev_col = next((h for h in reader.fieldnames if 'revenue' in h.lower() and 'total' in h.lower()), None)
        if not rev_col:
            # Try just 'revenue' if 'totalrevenue' not found
            rev_col = next((h for h in reader.fieldnames if 'revenue' in h.lower()), None)
            
        for row in reader:
            if rev_col and row[rev_col]:
                # Clean currency formatting
                val = row[rev_col].replace('$', '').replace(',', '').strip()
                try:
                    rows.append(float(val))
                except:
                    pass

    # Check monotonicity (Revenue should decrease from Q1 to Q5)
    is_monotonic = False
    if len(rows) >= 2:
        is_monotonic = all(rows[i] >= rows[i+1] for i in range(len(rows)-1))

    q1_val = rows[0] if len(rows) > 0 else 0
    q5_val = rows[-1] if len(rows) > 0 else 0
    
    print(json.dumps({
        'q1_revenue': q1_val,
        'q5_revenue': q5_val,
        'is_monotonic': is_monotonic,
        'row_count': len(rows),
        'valid_csv': True
    }))

except Exception as e:
    print(json.dumps({
        'q1_revenue': 0,
        'q5_revenue': 0,
        'is_monotonic': False,
        'row_count': 0,
        'valid_csv': False,
        'error': str(e)
    }))
")
PYEOF
    
    # Parse Python output
    Q1_REVENUE=$(echo "$CSV_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('q1_revenue', 0))")
    Q5_REVENUE=$(echo "$CSV_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('q5_revenue', 0))")
    MONOTONIC=$(echo "$CSV_JSON" | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('is_monotonic')).lower())")
    CSV_VALID=$(echo "$CSV_JSON" | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('valid_csv')).lower())")
fi

# 2. Check SQL Script
SQL_EXISTS="false"
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
fi

# 3. Load Ground Truth
GT_Q1_REVENUE=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['quintile_1']['revenue'])" 2>/dev/null || echo 0)

# 4. Check File Timestamp (Anti-gaming)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo 0)
FILE_CREATED_DURING_TASK="false"
if [ -f "$CSV_PATH" ]; then
    FILE_TIME=$(stat -c%Y "$CSV_PATH" 2>/dev/null || stat -f%m "$CSV_PATH" 2>/dev/null || echo 0)
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 5. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_valid": $CSV_VALID,
    "row_count": $ROW_COUNT,
    "q1_revenue": $Q1_REVENUE,
    "q5_revenue": $Q5_REVENUE,
    "is_monotonic": $MONOTONIC,
    "sql_exists": $SQL_EXISTS,
    "gt_q1_revenue": $GT_Q1_REVENUE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="