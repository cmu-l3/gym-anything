#!/bin/bash
echo "=== Exporting Configure Report ACL Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for the User Group configuration
# We fetch specific fields to verify: allowed_reports and force_change_password
echo "Querying Vicidial database..."

DB_RESULT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT user_group, allowed_reports, force_change_password 
     FROM vicidial_user_groups 
     WHERE user_group='SUP_SECURE';" 2>/dev/null || true)

# 3. Get total group count to check if a new group was actually created
FINAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT COUNT(*) FROM vicidial_user_groups;" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_group_count.txt 2>/dev/null || echo "0")

# Parse DB Result
GROUP_EXISTS="false"
ALLOWED_REPORTS=""
FORCE_PWD=""

if [ -n "$DB_RESULT" ]; then
    GROUP_EXISTS="true"
    # MySQL output is tab-separated. 
    # Field 1: user_group (SUP_SECURE)
    # Field 2: allowed_reports (text blob)
    # Field 3: force_change_password (Y/N)
    
    # Use awk to extract fields safely
    ALLOWED_REPORTS=$(echo "$DB_RESULT" | awk -F'\t' '{print $2}')
    FORCE_PWD=$(echo "$DB_RESULT" | awk -F'\t' '{print $3}')
fi

# 4. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "group_exists": $GROUP_EXISTS,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "config": {
        "allowed_reports": "$ALLOWED_REPORTS",
        "force_change_password": "$FORCE_PWD"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="