#!/bin/bash
# export_result.sh — Export data for verifier
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Capturing final state screenshot..."
take_screenshot /tmp/task_final.png

# Query the database for the weight entries of the admin user
ADMIN_ID=$(db_query "SELECT id FROM auth_user WHERE username='admin'")

# 1. Total entries (should remain 30, proving they didn't just delete them)
TOTAL_ENTRIES=$(db_query "SELECT COUNT(*) FROM weight_weightentry WHERE user_id=${ADMIN_ID}" 2>/dev/null || echo "0")

# 2. Outlier entries (should be 0, proving they fixed the spikes)
OUTLIER_ENTRIES=$(db_query "SELECT COUNT(*) FROM weight_weightentry WHERE user_id=${ADMIN_ID} AND weight > 150" 2>/dev/null || echo "0")

# 3. Valid entries (should be 30, proving the math was correctly applied to put them back in the 70-100kg range)
VALID_ENTRIES=$(db_query "SELECT COUNT(*) FROM weight_weightentry WHERE user_id=${ADMIN_ID} AND weight >= 70 AND weight <= 100" 2>/dev/null || echo "0")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "total_entries": $TOTAL_ENTRIES,
    "outlier_entries": $OUTLIER_ENTRIES,
    "valid_entries": $VALID_ENTRIES,
    "initial_outliers": $(cat /tmp/initial_outliers.txt 2>/dev/null || echo "5")
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="