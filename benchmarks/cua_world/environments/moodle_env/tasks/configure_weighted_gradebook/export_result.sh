#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Query Moodle database for gradebook configuration
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='ENG201'")

if [ -n "$COURSE_ID" ]; then
    echo "Found Course ID: $COURSE_ID. Dumping gradebook structure..."
    
    # Export categories (includes aggregation types and names)
    moodle_query_headers "SELECT id, parent, fullname, aggregation, timecreated, timemodified FROM mdl_grade_categories WHERE courseid=$COURSE_ID" > /tmp/grade_categories.tsv
    
    # Export items (includes manual items, weights, max grades)
    moodle_query_headers "SELECT id, categoryid, itemname, itemtype, iteminstance, grademax, aggregationcoef, aggregationcoef2, timecreated, timemodified FROM mdl_grade_items WHERE courseid=$COURSE_ID" > /tmp/grade_items.tsv
else
    echo "Course ENG201 not found!"
    echo -e "id\tparent\tfullname\taggregation\ttimecreated\ttimemodified" > /tmp/grade_categories.tsv
    echo -e "id\tcategoryid\titemname\titemtype\titeminstance\tgrademax\taggregationcoef\taggregationcoef2\ttimecreated\ttimemodified" > /tmp/grade_items.tsv
fi

# Use Python to parse TSVs into a structured JSON for the verifier
python3 - << 'EOF'
import csv
import json
import sys

def tsv_to_dict(filepath):
    try:
        with open(filepath, 'r') as f:
            reader = csv.DictReader(f, delimiter='\t')
            return [dict(row) for row in reader]
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return []

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

categories = tsv_to_dict('/tmp/grade_categories.tsv')
items = tsv_to_dict('/tmp/grade_items.tsv')

output = {
    "task_start_time": task_start,
    "course_exists": len(categories) > 0,
    "categories": categories,
    "items": items,
    "screenshot_path": "/tmp/task_final.png"
}

try:
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(output, f, indent=2)
    print("Result JSON saved successfully to /tmp/task_result.json")
except Exception as e:
    print(f"Failed to write JSON: {e}")
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="