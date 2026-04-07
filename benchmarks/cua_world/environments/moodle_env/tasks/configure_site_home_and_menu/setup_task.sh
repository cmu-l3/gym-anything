#!/bin/bash
# Setup script for Configure Site Home and Menu task

echo "=== Setting up Configure Site Home and Menu Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if sourcing fails
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
    wait_for_window() {
        local window_pattern="$1"
        local timeout=${2:-30}
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then return 0; fi
            sleep 1; elapsed=$((elapsed + 1))
        done
        return 1
    }
    get_firefox_window_id() { DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'; }
    focus_window() { DISPLAY=:1 wmctrl -ia "$1" 2>/dev/null || true; sleep 0.3; }
fi

# Record initial site config for verification (Anti-gaming)
echo "Recording initial site configuration..."

# Get initial Site Course details (ID=1)
INITIAL_FULLNAME=$(moodle_query "SELECT fullname FROM mdl_course WHERE id=1" | tr -d '\n')
INITIAL_SHORTNAME=$(moodle_query "SELECT shortname FROM mdl_course WHERE id=1" | tr -d '\n')
INITIAL_MENU=$(moodle_query "SELECT value FROM mdl_config WHERE name='custommenuitems'" | tr -d '\n')

# Save to temp file
cat > /tmp/initial_site_config.json << EOF
{
    "fullname": "$(echo "$INITIAL_FULLNAME" | sed 's/"/\\"/g')",
    "shortname": "$(echo "$INITIAL_SHORTNAME" | sed 's/"/\\"/g')",
    "custommenuitems": "$(echo "$INITIAL_MENU" | sed 's/"/\\"/g')"
}
EOF

echo "Initial config recorded."

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="