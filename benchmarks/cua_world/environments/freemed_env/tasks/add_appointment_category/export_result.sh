#!/bin/bash
# Export script for Add Appointment Category task

echo "=== Exporting Add Appointment Category Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Take a post-task database snapshot to find the new category
echo "Dumping database to search for new category..."
mysqldump -u freemed -pfreemed --skip-extended-insert freemed > /tmp/db_dump_after.sql 2>/dev/null || true

DB_MATCH="false"
DURATION_MATCH="false"
NEWLY_CREATED="false"
MATCHING_LINES=""

# Search the database dump for the target category name
if grep -i -q "Diabetes Education" /tmp/db_dump_after.sql; then
    DB_MATCH="true"
    
    # Extract the line(s) where it was found
    MATCHING_LINES=$(grep -i "Diabetes Education" /tmp/db_dump_after.sql | head -n 5)
    
    # Check if the extracted line also contains the expected duration (45)
    # Using regex to ensure 45 is a distinct number (e.g., ,45, or '45')
    if echo "$MATCHING_LINES" | grep -qE "[^0-9]45[^0-9]"; then
        DURATION_MATCH="true"
    fi
    
    # Anti-gaming check: Verify the record did NOT exist in the pre-task dump
    if [ -f /tmp/db_dump_before.sql ]; then
        if ! grep -i -q "Diabetes Education" /tmp/db_dump_before.sql; then
            NEWLY_CREATED="true"
        fi
    else
        # If before-dump failed for some reason, we default to false or rely on timestamp
        NEWLY_CREATED="false"
    fi
fi

# Use Python to safely format the JSON result output, avoiding bash quoting issues
python3 -c '
import json
import sys

db_match = sys.argv[1].lower() == "true"
duration_match = sys.argv[2].lower() == "true"
newly_created = sys.argv[3].lower() == "true"
matching_lines = sys.argv[4]

result = {
    "db_match": db_match,
    "duration_match": duration_match,
    "newly_created": newly_created,
    "matching_lines": matching_lines,
    "export_timestamp": True
}

with open("/tmp/appointment_category_result.json", "w") as f:
    json.dump(result, f, indent=4)
' "$DB_MATCH" "$DURATION_MATCH" "$NEWLY_CREATED" "$MATCHING_LINES"

# Set permissions
chmod 666 /tmp/appointment_category_result.json 2>/dev/null || sudo chmod 666 /tmp/appointment_category_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/appointment_category_result.json"
cat /tmp/appointment_category_result.json

echo ""
echo "=== Export Complete ==="