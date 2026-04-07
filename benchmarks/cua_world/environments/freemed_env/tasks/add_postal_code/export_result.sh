#!/bin/bash
echo "=== Exporting add_postal_code Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_postal_end.png

# Take a full schema-agnostic DB dump for the final state
echo "Capturing final database state..."
mysqldump -u freemed -pfreemed freemed > /tmp/final_dump.sql 2>/dev/null

# 1. Programmatic DB Check: Explicit table query (Primary check)
FINAL_COUNT=$(freemed_query "SELECT COUNT(*) FROM zipcodes" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_zip_count 2>/dev/null || echo "0")

ZIP_EXISTS=$(freemed_query "SELECT COUNT(*) FROM zipcodes WHERE zip='60523'" 2>/dev/null || echo "0")
CITY_EXISTS=$(freemed_query "SELECT COUNT(*) FROM zipcodes WHERE zip='60523' AND city LIKE '%Oak Brook%'" 2>/dev/null || echo "0")
STATE_EXISTS=$(freemed_query "SELECT COUNT(*) FROM zipcodes WHERE zip='60523' AND state='IL'" 2>/dev/null || echo "0")

# 2. Schema-agnostic fallback: Search dumps directly
INIT_HAS_ZIP="false"
FINAL_HAS_ZIP="false"
FINAL_HAS_CITY="false"

if grep -qi "60523" /tmp/initial_dump.sql; then INIT_HAS_ZIP="true"; fi
if grep -qi "60523" /tmp/final_dump.sql; then FINAL_HAS_ZIP="true"; fi
if grep -qi "Oak Brook" /tmp/final_dump.sql; then FINAL_HAS_CITY="true"; fi

# Determine if the record was newly added during the task
NEWLY_ADDED="false"
if [ "$FINAL_COUNT" -gt "$INITIAL_COUNT" ] || [ "$INIT_HAS_ZIP" = "false" -a "$FINAL_HAS_ZIP" = "true" ]; then
    NEWLY_ADDED="true"
fi

# Create secure temporary JSON
TEMP_JSON=$(mktemp /tmp/postal_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_checks": {
        "initial_count": ${INITIAL_COUNT:-0},
        "final_count": ${FINAL_COUNT:-0},
        "zip_record_count": ${ZIP_EXISTS:-0},
        "city_match_count": ${CITY_EXISTS:-0},
        "state_match_count": ${STATE_EXISTS:-0}
    },
    "dump_checks": {
        "initial_has_zip": $INIT_HAS_ZIP,
        "final_has_zip": $FINAL_HAS_ZIP,
        "final_has_city": $FINAL_HAS_CITY
    },
    "newly_added": $NEWLY_ADDED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy to standard readable location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="