#!/bin/bash
# Export script for Configure Grade Letters task

echo "=== Exporting Configure Grade Letters Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read stored context ID
CONTEXT_ID=$(cat /tmp/target_context_id 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_letters_count 2>/dev/null || echo "0")

# Get current grade letters from database
# We select letter and lowerboundary for the specific course context
echo "Querying grade letters for context $CONTEXT_ID..."

# Fetch raw data: letter, lowerboundary
# We use a separator '|' to parse easily in python/bash
LETTERS_DATA=$(moodle_query "SELECT letter, lowerboundary FROM mdl_grade_letters WHERE contextid=$CONTEXT_ID ORDER BY lowerboundary DESC")

# Count records
CURRENT_COUNT=$(echo "$LETTERS_DATA" | grep -v "^$" | wc -l)

echo "Found $CURRENT_COUNT grade letters (Initial: $INITIAL_COUNT)"

# Convert to JSON structure
# We'll create a simple JSON object mapping letter -> boundary
JSON_BOUNDARIES="{"
FIRST=1

while IFS=$'\t' read -r letter boundary; do
    if [ -n "$letter" ]; then
        if [ $FIRST -eq 0 ]; then
            JSON_BOUNDARIES="$JSON_BOUNDARIES, "
        fi
        # Clean up boundary (remove trailing zeros if desired, but float parsing handles it)
        # Escape letter (though usually safe A, A-, etc)
        JSON_BOUNDARIES="$JSON_BOUNDARIES \"$letter\": $boundary"
        FIRST=0
    fi
done <<< "$LETTERS_DATA"

JSON_BOUNDARIES="$JSON_BOUNDARIES}"

# Check timestamp of latest modification
# Moodle doesn't store timestamps in mdl_grade_letters directly, 
# but we can check if the count changed or if records exist now.
# We trust the data state relative to the initial reset.

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/grade_letters_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "context_id": $CONTEXT_ID,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "boundaries": $JSON_BOUNDARIES,
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo ""
echo "Exported Result:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="