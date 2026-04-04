#!/bin/bash
echo "=== Exporting Create Student Profile result ==="

# Load utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find the GCompris database
DB_FILE=$(find /home/ga/.local/share/GCompris -name "GCompris-*.db" | head -n 1)

# Initialize result variables
USER_FOUND="false"
FIRST_NAME_MATCH="false"
LAST_NAME_MATCH="false"
BIRTH_YEAR_MATCH="false"
NEW_USER_COUNT="0"
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
DB_MODIFIED="false"

if [ -f "$DB_FILE" ]; then
    # Check if DB was modified during task
    DB_MTIME=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo "0")
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi

    # Query the database for the specific user "Alex Miller"
    # We use a python script to handle the sqlite interaction robustly
    cat > /tmp/query_db.py << 'EOF'
import sqlite3
import json
import sys
import datetime

db_path = sys.argv[1]
try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # Get total count
    c.execute('SELECT COUNT(*) FROM users')
    total_count = c.fetchone()[0]
    
    # Query for Alex Miller
    # Note: Schema usually has 'firstname', 'lastname', 'birthdate' (sometimes as timestamp or string)
    c.execute("SELECT firstname, lastname, birthdate FROM users WHERE firstname='Alex'")
    rows = c.fetchall()
    
    found_user = None
    best_match = {"firstname": False, "lastname": False, "birthyear": False}
    
    for row in rows:
        fname, lname, bdate = row
        match = {"firstname": True, "lastname": False, "birthyear": False}
        
        # Check Last Name
        if lname and lname.lower() == 'miller':
            match["lastname"] = True
            
        # Check Birth Year
        # bdate formats vary, usually YYYY-MM-DD or similar string
        if bdate:
            bdate_str = str(bdate)
            if '2018' in bdate_str:
                match["birthyear"] = True
        
        # If this is a better match than previous, keep it
        score = sum(match.values())
        best_score = sum(best_match.values())
        
        if score > best_score:
            best_match = match
            found_user = row

    result = {
        "user_found": len(rows) > 0,
        "matches": best_match,
        "total_count": total_count,
        "error": None
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e), "user_found": False, "total_count": 0}))
EOF

    # Run the query
    QUERY_RESULT=$(python3 /tmp/query_db.py "$DB_FILE")
    
    # Parse results
    USER_FOUND=$(echo "$QUERY_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('user_found', False))" 2>/dev/null || echo "false")
    # Python boolean to bash string conversion
    if [ "$USER_FOUND" = "True" ]; then USER_FOUND="true"; else USER_FOUND="false"; fi
    
    FIRST_NAME_MATCH=$(echo "$QUERY_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('matches', {}).get('firstname', False))" 2>/dev/null || echo "false")
    if [ "$FIRST_NAME_MATCH" = "True" ]; then FIRST_NAME_MATCH="true"; else FIRST_NAME_MATCH="false"; fi
    
    LAST_NAME_MATCH=$(echo "$QUERY_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('matches', {}).get('lastname', False))" 2>/dev/null || echo "false")
    if [ "$LAST_NAME_MATCH" = "True" ]; then LAST_NAME_MATCH="true"; else LAST_NAME_MATCH="false"; fi
    
    BIRTH_YEAR_MATCH=$(echo "$QUERY_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('matches', {}).get('birthyear', False))" 2>/dev/null || echo "false")
    if [ "$BIRTH_YEAR_MATCH" = "True" ]; then BIRTH_YEAR_MATCH="true"; else BIRTH_YEAR_MATCH="false"; fi
    
    NEW_USER_COUNT=$(echo "$QUERY_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total_count', 0))" 2>/dev/null || echo "0")
fi

# Check if application was still running
APP_RUNNING=$(pgrep -f "gcompris" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_found": $([ -f "$DB_FILE" ] && echo "true" || echo "false"),
    "db_modified": $DB_MODIFIED,
    "user_found": $USER_FOUND,
    "first_name_match": $FIRST_NAME_MATCH,
    "last_name_match": $LAST_NAME_MATCH,
    "birth_year_match": $BIRTH_YEAR_MATCH,
    "initial_user_count": $INITIAL_USER_COUNT,
    "final_user_count": $NEW_USER_COUNT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="