#!/bin/bash
# Task export: delete_outlier_measurements
# Queries the database for the remaining outlier and valid measurement entries.

echo "=== Exporting delete_outlier_measurements result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the current state
echo "Querying database for measurement counts..."

# Query 1: Body Fat Outliers (> 100)
OUTLIER_BF=$(db_query "SELECT COUNT(*) FROM measurements_measurement m JOIN measurements_category c ON m.category_id = c.id WHERE c.name = 'Body Fat' AND m.value > 100;" | tr -d '\r\n')

# Query 2: Waist Outliers (> 800)
OUTLIER_WAIST=$(db_query "SELECT COUNT(*) FROM measurements_measurement m JOIN measurements_category c ON m.category_id = c.id WHERE c.name = 'Waist' AND m.value > 800;" | tr -d '\r\n')

# Query 3: Valid Body Fat (<= 100)
VALID_BF=$(db_query "SELECT COUNT(*) FROM measurements_measurement m JOIN measurements_category c ON m.category_id = c.id WHERE c.name = 'Body Fat' AND m.value <= 100;" | tr -d '\r\n')

# Query 4: Valid Waist (<= 800)
VALID_WAIST=$(db_query "SELECT COUNT(*) FROM measurements_measurement m JOIN measurements_category c ON m.category_id = c.id WHERE c.name = 'Waist' AND m.value <= 800;" | tr -d '\r\n')

# Default to 0 if queries fail
OUTLIER_BF=${OUTLIER_BF:-0}
OUTLIER_WAIST=${OUTLIER_WAIST:-0}
VALID_BF=${VALID_BF:-0}
VALID_WAIST=${VALID_WAIST:-0}

echo "Results - BF Outliers: $OUTLIER_BF, Waist Outliers: $OUTLIER_WAIST, Valid BF: $VALID_BF, Valid Waist: $VALID_WAIST"

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "outlier_bf_count": $OUTLIER_BF,
    "outlier_waist_count": $OUTLIER_WAIST,
    "valid_bf_count": $VALID_BF,
    "valid_waist_count": $VALID_WAIST,
    "task_end_time": $(date +%s)
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="