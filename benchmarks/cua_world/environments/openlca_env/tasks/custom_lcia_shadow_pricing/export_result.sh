#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Custom LCIA Shadow Pricing Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Identify result file status
RESULT_FILE="/home/ga/LCA_Results/shadow_price_result.csv"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$RESULT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Close OpenLCA to query the Derby database safely
close_openlca
sleep 3

# 4. Find the active database
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find largest DB (assuming it's the one with USLCI imported)
for db_path in "$DB_DIR"/*/; do
    if [ -d "$db_path" ]; then
        SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1)
        if [ "${SIZE:-0}" -gt "$MAX_SIZE" ]; then
            MAX_SIZE=$SIZE
            ACTIVE_DB="$db_path"
        fi
    fi
done

# 5. Query Derby DB for Method, Category, and Factors
METHOD_FOUND="false"
CATEGORY_FOUND="false"
FACTORS_JSON="[]"

if [ -n "$ACTIVE_DB" ]; then
    echo "Querying database: $ACTIVE_DB"

    # Check Method
    METHOD_QUERY="SELECT NAME FROM TBL_IMPACT_METHODS WHERE LOWER(NAME) LIKE '%shadow price%';"
    METHOD_RES=$(derby_query "$ACTIVE_DB" "$METHOD_QUERY")
    if echo "$METHOD_RES" | grep -qi "Shadow Price"; then
        METHOD_FOUND="true"
    fi

    # Check Category
    CAT_QUERY="SELECT NAME FROM TBL_IMPACT_CATEGORIES WHERE LOWER(NAME) LIKE '%carbon liability%';"
    CAT_RES=$(derby_query "$ACTIVE_DB" "$CAT_QUERY")
    if echo "$CAT_RES" | grep -qi "Carbon Liability"; then
        CATEGORY_FOUND="true"
    fi

    # Check Factors (Complex Join)
    # We want to find factors linked to our category and see the flow names and values
    # Note: Derby SQL syntax
    FACTOR_QUERY="SELECT f.NAME, fac.VALUE \
                  FROM TBL_IMPACT_FACTORS fac \
                  JOIN TBL_FLOWS f ON fac.FLOW_ID = f.ID \
                  JOIN TBL_IMPACT_CATEGORIES cat ON fac.CATEGORY_ID = cat.ID \
                  WHERE LOWER(cat.NAME) LIKE '%carbon liability%';"
    
    FACTOR_RES=$(derby_query "$ACTIVE_DB" "$FACTOR_QUERY")
    
    # Process the factor result into a JSON array using Python for robustness
    FACTORS_JSON=$(python3 -c "
import sys
import json
import re

input_text = '''$FACTOR_RES'''
factors = []

# Parse Derby output which looks like:
# NAME                                |VALUE
# ------------------------------------------
# Carbon dioxide                      |0.1
# Methane                             |2.5

lines = input_text.split('\n')
for line in lines:
    # Skip header/separator lines
    if 'NAME' in line or '---' in line or 'rows selected' in line or line.strip() == '':
        continue
        
    parts = line.split('|')
    if len(parts) >= 2:
        name = parts[0].strip()
        try:
            val = float(parts[1].strip())
            factors.append({'flow': name, 'value': val})
        except ValueError:
            pass

print(json.dumps(factors))
")
fi

# 6. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "method_found": $METHOD_FOUND,
    "category_found": $CATEGORY_FOUND,
    "factors": $FACTORS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="