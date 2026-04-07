#!/bin/bash
set -e
echo "=== Exporting create_gradebook_assignment results ==="

# DB Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -B -e"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for Results
# We need to find:
# A. The 'Projects' assignment type for the General Science course
# B. The 'Science Fair Project' assignment linked to that type

echo "Querying database..."

# Helper to execute query and output JSON-safe string
query_to_json() {
    local sql="$1"
    # Execute, skip header (-N), tab separated
    # Use python to convert tab-separated output to JSON list of dicts if needed, 
    # but here we'll just dump the raw fields for the verifier to parse
    $MYSQL_CMD "$sql"
}

# Get Course Period ID for General Science
CP_ID=$($MYSQL_CMD "SELECT course_period_id FROM course_periods JOIN courses ON course_periods.course_id = courses.course_id WHERE courses.course_code='SCI101' LIMIT 1")

# Check Assignment Type (Category)
# Schema assumption: gradebook_assignment_types (assignment_type_id, title, course_period_id, final_grade_percent)
TYPE_DATA=$($MYSQL_CMD "SELECT assignment_type_id, title, final_grade_percent FROM gradebook_assignment_types WHERE course_period_id='$CP_ID' AND title='Projects'")

# Check Assignment
# Schema assumption: gradebook_assignments (assignment_id, assignment_type_id, title, points, due_date)
# We look for the assignment regardless of type first to debug, then check type linkage
ASSIGNMENT_DATA=$($MYSQL_CMD "SELECT assignment_id, assignment_type_id, title, points, due_date FROM gradebook_assignments WHERE course_period_id='$CP_ID' AND title='Science Fair Project'")

# Check if DB records exist
TYPE_FOUND="false"
if [ -n "$TYPE_DATA" ]; then TYPE_FOUND="true"; fi

ASSIGNMENT_FOUND="false"
if [ -n "$ASSIGNMENT_DATA" ]; then ASSIGNMENT_FOUND="true"; fi

# 3. Construct JSON Result
# We use Python to robustly construct the JSON to avoid string escaping issues in bash
python3 -c "
import json
import sys

try:
    type_raw = '''$TYPE_DATA'''
    assign_raw = '''$ASSIGNMENT_DATA'''
    
    result = {
        'category_found': False,
        'assignment_found': False,
        'category': {},
        'assignment': {}
    }

    if type_raw.strip():
        parts = type_raw.strip().split('\t')
        if len(parts) >= 2:
            result['category_found'] = True
            result['category'] = {
                'id': parts[0],
                'title': parts[1],
                'weight': parts[2] if len(parts) > 2 else '0'
            }

    if assign_raw.strip():
        parts = assign_raw.strip().split('\t')
        if len(parts) >= 5:
            result['assignment_found'] = True
            result['assignment'] = {
                'id': parts[0],
                'type_id': parts[1],
                'title': parts[2],
                'points': parts[3],
                'due_date': parts[4]
            }

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)

except Exception as e:
    print(f'Error constructing JSON: {e}')
    # Fallback empty JSON
    with open('/tmp/task_result.json', 'w') as f:
        f.write('{}')
"

# Set permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json