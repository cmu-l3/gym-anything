#!/bin/bash
echo "=== Exporting task results ==="

# Source credentials if needed, or define them
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query Database for the Grade Scale
# We fetch the scale details and all associated grades
echo "Querying database for 'Standard 4.0 Scale'..."

# First check if the parent scale exists
SCALE_ID=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -e "SELECT id FROM report_card_grade_scales WHERE title = 'Standard 4.0 Scale' LIMIT 1" 2>/dev/null || echo "")

SCALE_FOUND="false"
GRADES_JSON="[]"

if [ -n "$SCALE_ID" ]; then
    SCALE_FOUND="true"
    
    # Fetch all grades associated with this scale
    # Using python to format SQL output safely as JSON to avoid CSV parsing issues
    GRADES_JSON=$(python3 -c "
import mysql.connector
import json

try:
    conn = mysql.connector.connect(
        user='$DB_USER', 
        password='$DB_PASS', 
        host='localhost', 
        database='$DB_NAME'
    )
    cursor = conn.cursor(dictionary=True)
    
    query = \"\"\"
        SELECT title, gpa_value, break_off, comment 
        FROM report_card_grades 
        WHERE grade_scale_id = $SCALE_ID 
        ORDER BY break_off DESC
    \"\"\"
    
    cursor.execute(query)
    rows = cursor.fetchall()
    
    # Convert Decimals to float for JSON serialization
    for row in rows:
        for key, val in row.items():
            if hasattr(val, 'to_eng_string'): # Handle Decimal objects
                row[key] = float(val)
                
    print(json.dumps(rows))
    
except Exception as e:
    print('[]')
")
fi

# 4. Anti-gaming checks
INITIAL_SCALE_COUNT=$(cat /tmp/initial_scale_count.txt 2>/dev/null || echo "0")
INITIAL_GRADE_COUNT=$(cat /tmp/initial_grade_count.txt 2>/dev/null || echo "0")

CURRENT_SCALE_COUNT=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -e "SELECT COUNT(*) FROM report_card_grade_scales" 2>/dev/null || echo "0")
CURRENT_GRADE_COUNT=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -e "SELECT COUNT(*) FROM report_card_grades" 2>/dev/null || echo "0")

# 5. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "scale_found": $SCALE_FOUND,
    "scale_id": "$SCALE_ID",
    "grades": $GRADES_JSON,
    "counts": {
        "initial_scales": $INITIAL_SCALE_COUNT,
        "current_scales": $CURRENT_SCALE_COUNT,
        "initial_grades": $INITIAL_GRADE_COUNT,
        "current_grades": $CURRENT_GRADE_COUNT
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="