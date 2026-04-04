#!/bin/bash
set -e

echo "=== Exporting Configure Voicemail Box Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot "/tmp/task_final.png"

# 2. Check if Firefox is still running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Query Database for the result
# We use docker exec to run the query inside the container
# We fetch the specific columns we care about for ID 8500
echo "Querying database..."

# Construct SQL query
SQL="SELECT voicemail_id, fullname, pass, email, active, delete_vm_after_email, zone FROM vicidial_voicemail WHERE voicemail_id='8500';"

# Run query via Docker
# Output format: tab-separated
DB_RESULT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "$SQL" 2>/dev/null || echo "")

# Parse result
EXISTS="false"
VOICEMAIL_ID=""
FULLNAME=""
PASS=""
EMAIL=""
ACTIVE=""
DELETE_VM=""
ZONE=""

if [ -n "$DB_RESULT" ]; then
    EXISTS="true"
    # Read fields into variables
    VOICEMAIL_ID=$(echo "$DB_RESULT" | cut -f1)
    FULLNAME=$(echo "$DB_RESULT" | cut -f2)
    PASS=$(echo "$DB_RESULT" | cut -f3)
    EMAIL=$(echo "$DB_RESULT" | cut -f4)
    ACTIVE=$(echo "$DB_RESULT" | cut -f5)
    DELETE_VM=$(echo "$DB_RESULT" | cut -f6)
    ZONE=$(echo "$DB_RESULT" | cut -f7)
fi

# 4. Create JSON Result
# Use a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape strings for JSON (basic)
FULLNAME_ESC=$(echo "$FULLNAME" | sed 's/"/\\"/g')
EMAIL_ESC=$(echo "$EMAIL" | sed 's/"/\\"/g')
ZONE_ESC=$(echo "$ZONE" | sed 's/"/\\"/g')

cat > "$TEMP_JSON" << EOF
{
    "app_running": $APP_RUNNING,
    "record_exists": $EXISTS,
    "voicemail_id": "$VOICEMAIL_ID",
    "fullname": "$FULLNAME_ESC",
    "password": "$PASS",
    "email": "$EMAIL_ESC",
    "active": "$ACTIVE",
    "delete_vm_after_email": "$DELETE_VM",
    "zone": "$ZONE_ESC",
    "task_end_timestamp": $(date +%s)
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json