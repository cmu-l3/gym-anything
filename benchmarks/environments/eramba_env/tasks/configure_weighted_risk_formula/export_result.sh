#!/bin/bash
echo "=== Exporting configure_weighted_risk_formula result ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query the database for the current configuration
# Eramba stores formulas in the 'risk_calculations' table.
# Columns typically: id, model, name, calculation, method, etc.
# We are looking for model='Risks' (Asset Risks)
echo "Querying database for final formula..."

# Get the formula string
FINAL_FORMULA=$(eramba_db_query "SELECT calculation FROM risk_calculations WHERE model='Risks' LIMIT 1;")

# Get the modification time
MODIFIED_TIME_STR=$(eramba_db_query "SELECT modified FROM risk_calculations WHERE model='Risks' LIMIT 1;")
# Convert MySQL datetime to timestamp for comparison (if possible, otherwise string compare)
# We'll just pass the string to python to parse

# Get initial formula for comparison
INITIAL_FORMULA=$(cat /tmp/initial_formula.txt 2>/dev/null || echo "")

# 2. Check if settings page was accessed (Anti-gaming/Trajectory proxy)
# We can't easily check access logs in this env, so we rely on the DB change + screenshots

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_formula": "$(echo "$INITIAL_FORMULA" | sed 's/"/\\"/g')",
    "final_formula": "$(echo "$FINAL_FORMULA" | sed 's/"/\\"/g')",
    "modified_timestamp": "$MODIFIED_TIME_STR",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="