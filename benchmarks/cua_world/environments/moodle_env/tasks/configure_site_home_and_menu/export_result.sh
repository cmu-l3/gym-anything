#!/bin/bash
# Export script for Configure Site Home and Menu task

echo "=== Exporting Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
    safe_write_json() {
        local temp_file="$1"; local dest_path="$2"
        rm -f "$dest_path" 2>/dev/null || true
        cp "$temp_file" "$dest_path"; chmod 666 "$dest_path" 2>/dev/null || true
        rm -f "$temp_file"; echo "Result saved to $dest_path"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query Current Site Identity (Course ID 1)
CURRENT_FULLNAME=$(moodle_query "SELECT fullname FROM mdl_course WHERE id=1")
CURRENT_SHORTNAME=$(moodle_query "SELECT shortname FROM mdl_course WHERE id=1")
CURRENT_SUMMARY=$(moodle_query "SELECT summary FROM mdl_course WHERE id=1")

# Query Custom Menu Items
CURRENT_MENU=$(moodle_query "SELECT value FROM mdl_config WHERE name='custommenuitems'")

# Escape special characters for JSON
CURRENT_FULLNAME_ESC=$(echo "$CURRENT_FULLNAME" | sed 's/"/\\"/g')
CURRENT_SHORTNAME_ESC=$(echo "$CURRENT_SHORTNAME" | sed 's/"/\\"/g')
CURRENT_SUMMARY_ESC=$(echo "$CURRENT_SUMMARY" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')
CURRENT_MENU_ESC=$(echo "$CURRENT_MENU" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/site_config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "fullname": "$CURRENT_FULLNAME_ESC",
    "shortname": "$CURRENT_SHORTNAME_ESC",
    "summary": "$CURRENT_SUMMARY_ESC",
    "custommenuitems": "$CURRENT_MENU_ESC",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/site_config_result.json

echo ""
cat /tmp/site_config_result.json
echo ""
echo "=== Export Complete ==="