#!/bin/bash
echo "=== Exporting Merge Task Results ==="

source /workspace/scripts/task_utils.sh

# Load config
if [ ! -f /tmp/merge_config.json ]; then
    echo "ERROR: Config file not found"
    exit 1
fi

MASTER_PID=$(jq -r '.master_pid' /tmp/merge_config.json)
DUP_PID=$(jq -r '.duplicate_pid' /tmp/merge_config.json)

# Check Database State
echo "Checking database state..."

# 1. Does Master exist?
MASTER_EXISTS=$(librehealth_query "SELECT COUNT(*) FROM patient_data WHERE pid=$MASTER_PID")

# 2. Does Duplicate exist?
DUP_EXISTS=$(librehealth_query "SELECT COUNT(*) FROM patient_data WHERE pid=$DUP_PID")

# 3. Total count of Cameron Fry
TOTAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM patient_data WHERE fname='Cameron' AND lname='Fry'")

# 4. Check if we have a "Merged" status in log/notes (Optional deep check)
# Ideally, we just check that data was consolidated, but existence is the primary proxy.

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "master_pid": $MASTER_PID,
    "duplicate_pid": $DUP_PID,
    "master_exists": $([ "$MASTER_EXISTS" -eq 1 ] && echo "true" || echo "false"),
    "duplicate_exists": $([ "$DUP_EXISTS" -eq 1 ] && echo "true" || echo "false"),
    "total_records_count": $TOTAL_COUNT,
    "timestamp": $(date +%s)
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported: master_exists=$MASTER_EXISTS, dup_exists=$DUP_EXISTS, total=$TOTAL_COUNT"