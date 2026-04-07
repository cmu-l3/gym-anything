#!/bin/bash
# Export script for Configure Course Sections task

echo "=== Exporting Configure Course Sections Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get Target Course ID
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null)
if [ -z "$COURSE_ID" ]; then
    # Fallback lookup
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='PHYS101'" | tr -d '[:space:]')
fi

echo "Checking sections for Course ID: $COURSE_ID"

# Prepare JSON output
# We will construct a JSON array of sections manually or via python because bash JSON handling is tricky
# We extract data to a temp file first

# Query: section number, name, visible, summary (hex encoded to avoid newline/quote issues in bash)
# Using HEX(summary) ensures we can handle HTML content safely
SECTIONS_DATA=$(moodle_query "SELECT section, name, visible, HEX(summary) FROM mdl_course_sections WHERE course=$COURSE_ID AND section BETWEEN 1 AND 5 ORDER BY section ASC")

# Use Python to parse the raw data and create the JSON
# Pass the data via a temp file
echo "$SECTIONS_DATA" > /tmp/sections_raw_data.tsv

python3 -c "
import json
import csv
import sys

sections = []
try:
    with open('/tmp/sections_raw_data.tsv', 'r') as f:
        # TSV from mysql -B
        reader = csv.reader(f, delimiter='\t')
        for row in reader:
            if len(row) >= 4:
                sec_num = row[0]
                name = row[1] if row[1] != 'NULL' else ''
                visible = row[2]
                summary_hex = row[3]
                
                # Decode summary
                summary = ''
                try:
                    summary = bytes.fromhex(summary_hex).decode('utf-8')
                except:
                    summary = ''

                sections.append({
                    'section': int(sec_num),
                    'name': name,
                    'visible': int(visible),
                    'summary': summary
                })
except Exception as e:
    print(f'Error parsing data: {e}', file=sys.stderr)

output = {
    'course_id': '$COURSE_ID',
    'sections': sections,
    'export_timestamp': '$(date -Iseconds)'
}

print(json.dumps(output, indent=2))
" > /tmp/configure_sections_result.json

# Safe move
safe_write_json /tmp/configure_sections_result.json /tmp/task_result.json

echo ""
echo "Exported Data:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="