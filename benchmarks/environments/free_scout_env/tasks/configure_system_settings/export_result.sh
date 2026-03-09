#!/bin/bash
echo "=== Exporting configure_system_settings result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Helper to get option value safely
get_option() {
    local name="$1"
    val=$(fs_query "SELECT value FROM options WHERE name='$name' LIMIT 1" 2>/dev/null)
    # Trim whitespace
    echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# ===== Get Current Values =====
CURRENT_COMPANY=$(get_option "company_name")
CURRENT_TIMEZONE=$(get_option "timezone")
CURRENT_TIMEFORMAT=$(get_option "time_format")

# ===== Get Initial Values =====
INITIAL_COMPANY=$(cat /tmp/initial_company_name.txt 2>/dev/null || echo "DEFAULT_EMPTY")
INITIAL_TIMEZONE=$(cat /tmp/initial_timezone.txt 2>/dev/null || echo "DEFAULT_EMPTY")
INITIAL_TIMEFORMAT=$(cat /tmp/initial_time_format.txt 2>/dev/null || echo "DEFAULT_EMPTY")

# ===== Check for Changes =====
CHANGED_COMPANY="false"
CHANGED_TIMEZONE="false"
CHANGED_TIMEFORMAT="false"

[ "$CURRENT_COMPANY" != "$INITIAL_COMPANY" ] && CHANGED_COMPANY="true"
[ "$CURRENT_TIMEZONE" != "$INITIAL_TIMEZONE" ] && CHANGED_TIMEZONE="true"
[ "$CURRENT_TIMEFORMAT" != "$INITIAL_TIMEFORMAT" ] && CHANGED_TIMEFORMAT="true"

# ===== JSON Export =====
# Escape strings for JSON safety
SAFE_COMPANY=$(echo "$CURRENT_COMPANY" | sed 's/"/\\"/g')
SAFE_TIMEZONE=$(echo "$CURRENT_TIMEZONE" | sed 's/"/\\"/g')
SAFE_TIMEFORMAT=$(echo "$CURRENT_TIMEFORMAT" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "current_company_name": "$SAFE_COMPANY",
    "current_timezone": "$SAFE_TIMEZONE",
    "current_time_format": "$SAFE_TIMEFORMAT",
    "changed_company": $CHANGED_COMPANY,
    "changed_timezone": $CHANGED_TIMEZONE,
    "changed_time_format": $CHANGED_TIMEFORMAT,
    "initial_company_name": "$(echo "$INITIAL_COMPANY" | sed 's/"/\\"/g')",
    "initial_timezone": "$(echo "$INITIAL_TIMEZONE" | sed 's/"/\\"/g')",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="