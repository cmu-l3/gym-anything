#!/bin/bash
echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Define Paths
OUTPUT_PATH="/home/ga/Documents/revenue_report.xlsx"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check file existence and metadata
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Verify Content using Python (inside container)
#    We do this here because the container has the exact pandas/env setup we prepared
#    and we want to produce a clean JSON for the host verifier.
echo "Running internal content verification..."

python3 - <<PYEOF
import pandas as pd
import json
import os
import sys

file_path = "$OUTPUT_PATH"
result = {
    "content_valid": False,
    "has_salespeople": False,
    "has_stages": False,
    "values_correct": False,
    "clean_measures": False,
    "error": ""
}

try:
    if os.path.exists(file_path):
        # Load Excel
        # Odoo pivot exports often have a specific structure.
        # Usually headers are on row 0 or 1.
        df = pd.read_excel(file_path)
        
        # Convert to string for broad searching
        content_str = df.to_string()
        
        result["content_valid"] = True
        
        # Check Rows (Salespeople)
        if "Alice Sales" in content_str and "Mitchell Admin" in content_str:
            result["has_salespeople"] = True
            
        # Check Columns (Stages)
        if "New" in content_str and "Won" in content_str:
            result["has_stages"] = True
            
        # Check Values
        # We look for specific revenue sums seeded in setup
        # Admin Won = 50000
        # Alice Qualified = 25000
        found_admin_won = False
        found_alice_qual = False
        
        # Iterate cells to find values
        for col in df.columns:
            for val in df[col]:
                try:
                    # Loose matching for formatted numbers if necessary, but Odoo export is usually raw number
                    if isinstance(val, (int, float)):
                        if abs(val - 50000) < 1: found_admin_won = True
                        if abs(val - 25000) < 1: found_alice_qual = True
                except:
                    pass
                    
        if found_admin_won and found_alice_qual:
            result["values_correct"] = True
            
        # Check Measures (Count should ideally be absent if user unchecked it)
        # This is a soft check
        headers = str(df.columns.tolist())
        if "Count" not in headers:
            result["clean_measures"] = True
            
except Exception as e:
    result["error"] = str(e)

# Write to temp result file
with open("/tmp/content_verification.json", "w") as f:
    json.dump(result, f)
PYEOF

# 5. Merge results into final JSON
# Read the content verification result
CONTENT_JSON=$(cat /tmp/content_verification.json 2>/dev/null || echo "{}")

# Create full result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "output_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "content_verification": $CONTENT_JSON
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json
echo "=== Export Done ==="