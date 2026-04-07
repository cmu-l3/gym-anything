#!/bin/bash
set -e
echo "=== Exporting Update Staff Profile Results ==="

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Target user details
FIRST_NAME="Robert"
LAST_NAME="Thompson"

# Check if database is accessible
if ! mysql -u $DB_USER -p"$DB_PASS" -e "SELECT 1" 2>/dev/null; then
    echo "ERROR: Cannot connect to database"
    echo '{"error": "Database connection failed"}' > /tmp/task_result.json
    exit 0
fi

# Query the CURRENT state of Robert Thompson
# We select fields to verify: title, email, and name (for integrity check)
echo "Querying database for Robert Thompson..."
QUERY="SELECT title, first_name, last_name, email 
       FROM staff 
       WHERE first_name='$FIRST_NAME' AND last_name='$LAST_NAME' 
       LIMIT 1"

# Execute query and format as tab-separated
RESULT=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -B -e "$QUERY" 2>/dev/null || echo "")

# Initialize variables
FOUND="false"
CUR_TITLE=""
CUR_FIRST=""
CUR_LAST=""
CUR_EMAIL=""

if [ -n "$RESULT" ]; then
    FOUND="true"
    CUR_TITLE=$(echo "$RESULT" | cut -f1)
    CUR_FIRST=$(echo "$RESULT" | cut -f2)
    CUR_LAST=$(echo "$RESULT" | cut -f3)
    CUR_EMAIL=$(echo "$RESULT" | cut -f4)
fi

# Retrieve initial values stored during setup (for anti-gaming)
INIT_TITLE=$(cat /tmp/initial_staff_title.txt 2>/dev/null || echo "Mr.")
INIT_EMAIL=$(cat /tmp/initial_staff_email.txt 2>/dev/null || echo "r.thompson@oldschool.edu")

# Escape for JSON
safe_json_str() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed "s/'/\\'/g"
}

JSON_TITLE=$(safe_json_str "$CUR_TITLE")
JSON_EMAIL=$(safe_json_str "$CUR_EMAIL")
JSON_FIRST=$(safe_json_str "$CUR_FIRST")
JSON_LAST=$(safe_json_str "$CUR_LAST")

# Create JSON result file
# We use a temporary file to avoid partial writes
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "record_found": $FOUND,
    "current_state": {
        "title": "$JSON_TITLE",
        "email": "$JSON_EMAIL",
        "first_name": "$JSON_FIRST",
        "last_name": "$JSON_LAST"
    },
    "initial_state": {
        "title": "$INIT_TITLE",
        "email": "$INIT_EMAIL"
    },
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="