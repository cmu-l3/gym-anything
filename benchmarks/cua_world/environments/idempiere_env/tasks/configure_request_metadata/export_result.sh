#!/bin/bash
echo "=== Exporting Configure Request Metadata results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for the created records
# We verify: Existence, Active Status, and Creation Time

# Query Helper
# output format: "ID|CREATED_TIMESTAMP|NAME"
get_record_info() {
    local table=$1
    local name=$2
    # psql returns empty string if no row found.
    # We select the record created most recently if duplicates exist (though setup cleans them).
    idempiere_query "SELECT $table.created FROM $table WHERE $table.name='$name' AND $table.ad_client_id=$CLIENT_ID AND $table.isactive='Y' ORDER BY $table.created DESC LIMIT 1"
}

echo "--- Querying Database ---"

# Check Request Type
TYPE_CREATED=$(get_record_info "r_requesttype" "Design Consultation")
if [ -n "$TYPE_CREATED" ]; then
    # Convert PostgreSQL timestamp to epoch if needed, or use python in verifier
    # Here we just pass the raw string string, but let's try to get epoch from SQL for easier bash comparison
    TYPE_EPOCH=$(idempiere_query "SELECT EXTRACT(EPOCH FROM created)::int FROM r_requesttype WHERE name='Design Consultation' AND ad_client_id=$CLIENT_ID AND isactive='Y' ORDER BY created DESC LIMIT 1")
else
    TYPE_EPOCH="0"
fi

# Check Request Category
CAT_EPOCH=$(idempiere_query "SELECT EXTRACT(EPOCH FROM created)::int FROM r_category WHERE name='Plant Selection' AND ad_client_id=$CLIENT_ID AND isactive='Y' ORDER BY created DESC LIMIT 1" 2>/dev/null || echo "0")
[ -z "$CAT_EPOCH" ] && CAT_EPOCH="0"

# Check Request Group
GRP_EPOCH=$(idempiere_query "SELECT EXTRACT(EPOCH FROM created)::int FROM r_group WHERE name='Design Team' AND ad_client_id=$CLIENT_ID AND isactive='Y' ORDER BY created DESC LIMIT 1" 2>/dev/null || echo "0")
[ -z "$GRP_EPOCH" ] && GRP_EPOCH="0"

# Check Request Resolution
RES_EPOCH=$(idempiere_query "SELECT EXTRACT(EPOCH FROM created)::int FROM r_resolution WHERE name='Proposal Accepted' AND ad_client_id=$CLIENT_ID AND isactive='Y' ORDER BY created DESC LIMIT 1" 2>/dev/null || echo "0")
[ -z "$RES_EPOCH" ] && RES_EPOCH="0"

# 3. Check if app was running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "records": {
        "request_type": {
            "found": $([ "$TYPE_EPOCH" -gt 0 ] && echo "true" || echo "false"),
            "created_epoch": $TYPE_EPOCH
        },
        "request_category": {
            "found": $([ "$CAT_EPOCH" -gt 0 ] && echo "true" || echo "false"),
            "created_epoch": $CAT_EPOCH
        },
        "request_group": {
            "found": $([ "$GRP_EPOCH" -gt 0 ] && echo "true" || echo "false"),
            "created_epoch": $GRP_EPOCH
        },
        "request_resolution": {
            "found": $([ "$RES_EPOCH" -gt 0 ] && echo "true" || echo "false"),
            "created_epoch": $RES_EPOCH
        }
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="