#!/bin/bash
# Export script for Configure Global Defaults task

echo "=== Exporting Configure Global Defaults Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper to get option value
get_option() {
    local name="$1"
    # Using 'limit 1' to handle potential duplicates if DB is messy, though option_name is usually unique/primary
    matomo_query "SELECT option_value FROM matomo_option WHERE option_name='$name' LIMIT 1"
}

echo "Querying current settings..."

# 1. General Settings
CURR_TZ=$(get_option "SitesManager_DefaultTimezone")
CURR_CURR=$(get_option "SitesManager_DefaultCurrency")

# 2. Personal Settings
# We check both potential key formats Matomo might use
CURR_PERIOD=$(get_option "UsersManager.userPreference.admin.defaultReport")
[ -z "$CURR_PERIOD" ] && CURR_PERIOD=$(get_option "UsersManager_userPreference_admin_defaultReport")

CURR_DATE=$(get_option "UsersManager.userPreference.admin.defaultReportDate")
[ -z "$CURR_DATE" ] && CURR_DATE=$(get_option "UsersManager_userPreference_admin_defaultReportDate")

echo "Current Values:"
echo "  Timezone: $CURR_TZ"
echo "  Currency: $CURR_CURR"
echo "  Period:   $CURR_PERIOD"
echo "  Date:     $CURR_DATE"

# Load initial baseline for comparison
INITIAL_TZ=""
INITIAL_CURR=""
INITIAL_PERIOD=""
INITIAL_DATE=""

if [ -f /tmp/initial_defaults.json ]; then
    # Simple extraction using grep/sed since we know the format from setup script
    INITIAL_TZ=$(grep "timezone" /tmp/initial_defaults.json | cut -d'"' -f4)
    INITIAL_CURR=$(grep "currency" /tmp/initial_defaults.json | cut -d'"' -f4)
    INITIAL_PERIOD=$(grep "report_period" /tmp/initial_defaults.json | cut -d'"' -f4)
    INITIAL_DATE=$(grep "report_date" /tmp/initial_defaults.json | cut -d'"' -f4)
fi

# Detect changes
CHANGED="false"
[ "$CURR_TZ" != "$INITIAL_TZ" ] && CHANGED="true"
[ "$CURR_CURR" != "$INITIAL_CURR" ] && CHANGED="true"
[ "$CURR_PERIOD" != "$INITIAL_PERIOD" ] && CHANGED="true"
[ "$CURR_DATE" != "$INITIAL_DATE" ] && CHANGED="true"

# JSON Escape
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

CURR_TZ_ESC=$(escape_json "$CURR_TZ")
CURR_CURR_ESC=$(escape_json "$CURR_CURR")
CURR_PERIOD_ESC=$(escape_json "$CURR_PERIOD")
CURR_DATE_ESC=$(escape_json "$CURR_DATE")

# Generate Result JSON
TEMP_JSON=$(mktemp /tmp/global_defaults_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "values_changed_from_baseline": $CHANGED,
    "initial": {
        "timezone": "$INITIAL_TZ",
        "currency": "$INITIAL_CURR",
        "report_period": "$INITIAL_PERIOD",
        "report_date": "$INITIAL_DATE"
    },
    "current": {
        "timezone": "$CURR_TZ_ESC",
        "currency": "$CURR_CURR_ESC",
        "report_period": "$CURR_PERIOD_ESC",
        "report_date": "$CURR_DATE_ESC"
    },
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/global_defaults_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/global_defaults_result.json
chmod 666 /tmp/global_defaults_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/global_defaults_result.json"
cat /tmp/global_defaults_result.json
echo ""
echo "=== Export Complete ==="