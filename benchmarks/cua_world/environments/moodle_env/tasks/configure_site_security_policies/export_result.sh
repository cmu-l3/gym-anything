#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Site Security Policies Result ==="

# 1. Take final screenshot (evidence of UI state)
take_screenshot /tmp/task_end_screenshot.png

# 2. Fetch current values for all relevant settings
# We defined the keys in setup, re-using list here
CONFIG_KEYS=(
    "passwordpolicy"
    "minpasswordlength"
    "minpassworddigits"
    "minpasswordlower"
    "minpasswordupper"
    "minpasswordnonalphanum"
    "maxconsecutiveidentchars"
    "lockoutthreshold"
    "lockoutwindow"
    "lockoutduration"
    "sessiontimeout"
)

# Build current state JSON
CURRENT_JSON="{"
first=true
for key in "${CONFIG_KEYS[@]}"; do
    val=$(moodle_query "SELECT value FROM mdl_config WHERE name='$key'" 2>/dev/null || echo "")
    # Trim whitespace just in case
    val=$(echo "$val" | tr -d '[:space:]')
    
    if [ "$first" = true ]; then
        first=false
    else
        CURRENT_JSON="$CURRENT_JSON,"
    fi
    CURRENT_JSON="$CURRENT_JSON \"$key\": \"$val\""
done
CURRENT_JSON="$CURRENT_JSON }"

# 3. Load initial state
INITIAL_STATE=$(cat /tmp/initial_config_state.json 2>/dev/null || echo "{}")

# 4. Construct final result JSON
TEMP_JSON=$(mktemp /tmp/security_policy_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "export_timestamp": "$(date -Iseconds)",
    "initial_state": $INITIAL_STATE,
    "current_state": $CURRENT_JSON
}
EOF

# 5. Save to final location with proper permissions
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="