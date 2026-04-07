#!/bin/bash
# Export script for Configure Automated Course Backups task

echo "=== Exporting Backup Configuration Result ==="

# Source shared utilities
# Note: We use explicit sourcing or fallback definition to ensure reliability
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback if util script is missing (safety)
    moodle_query() {
        mysql -u moodleuser -pmoodlepass moodle -N -B -e "$1" 2>/dev/null
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

# Helper to get a config value
# Usage: get_config_plugin "backup" "backup_auto_active"
get_config_plugin() {
    local plugin="$1"
    local name="$2"
    moodle_query "SELECT value FROM mdl_config_plugins WHERE plugin='$plugin' AND name='$name'"
}

# 1. Query Database for settings
echo "Querying database for backup settings..."

AUTO_ACTIVE=$(get_config_plugin "backup" "backup_auto_active")
AUTO_WEEKDAYS=$(get_config_plugin "backup" "backup_auto_weekdays")
AUTO_HOUR=$(get_config_plugin "backup" "backup_auto_hour")
AUTO_STORAGE=$(get_config_plugin "backup" "backup_auto_storage")
AUTO_DEST=$(get_config_plugin "backup" "backup_auto_destination")
AUTO_KEEP=$(get_config_plugin "backup" "backup_auto_keep")
AUTO_DELETE_OLD=$(get_config_plugin "backup" "backup_auto_delete_old")
AUTO_SKIP_HIDDEN=$(get_config_plugin "backup" "backup_auto_skip_hidden")

echo "Retrieved values:"
echo "Active: $AUTO_ACTIVE"
echo "Weekdays: $AUTO_WEEKDAYS"
echo "Hour: $AUTO_HOUR"
echo "Storage: $AUTO_STORAGE"
echo "Dest: $AUTO_DEST"
echo "Keep: $AUTO_KEEP"

# 2. Create JSON result
TEMP_JSON=$(mktemp /tmp/backup_config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "backup_auto_active": "${AUTO_ACTIVE:-0}",
    "backup_auto_weekdays": "${AUTO_WEEKDAYS:-}",
    "backup_auto_hour": "${AUTO_HOUR:-0}",
    "backup_auto_storage": "${AUTO_STORAGE:-0}",
    "backup_auto_destination": "${AUTO_DEST:-}",
    "backup_auto_keep": "${AUTO_KEEP:-0}",
    "backup_auto_delete_old": "${AUTO_DELETE_OLD:-0}",
    "backup_auto_skip_hidden": "${AUTO_SKIP_HIDDEN:-0}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# 3. Save to final location
safe_write_json "$TEMP_JSON" /tmp/backup_config_result.json

echo ""
cat /tmp/backup_config_result.json
echo ""
echo "=== Export Complete ==="