#!/bin/bash
# Setup script for Create Assignment task

echo "=== Setting up Create Assignment task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type sakai_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    sakai_query() {
        docker exec sakai-db mysql -u sakai -psakaipass sakai -N -B -e "$1" 2>/dev/null
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

# Verify BIO101 course site exists
TARGET_SITE="BIO101"
SITE_EXISTS=$(sakai_query "SELECT COUNT(*) FROM SAKAI_SITE WHERE SITE_ID='$TARGET_SITE'" | tr -d '[:space:]')
if [ "${SITE_EXISTS:-0}" -eq 0 ]; then
    echo "WARNING: BIO101 site not found! Assignments tool may not be accessible."
fi
echo "BIO101 site exists: $SITE_EXISTS"

# Verify Assignments tool is present
ASSGN_TOOL=$(sakai_query "SELECT COUNT(*) FROM SAKAI_SITE_TOOL WHERE SITE_ID='$TARGET_SITE' AND REGISTRATION='sakai.assignment.grades'" | tr -d '[:space:]')
echo "Assignments tool in BIO101: $ASSGN_TOOL"

# Record baseline assignment count
INITIAL_ASSIGNMENT_COUNT=$(sakai_query "SELECT COUNT(*) FROM ASN_ASSIGNMENT WHERE CONTEXT='$TARGET_SITE' AND DELETED=0" 2>/dev/null | tr -d '[:space:]')
INITIAL_ASSIGNMENT_COUNT=${INITIAL_ASSIGNMENT_COUNT:-0}
echo "$INITIAL_ASSIGNMENT_COUNT" > /tmp/initial_assignment_count
echo "Initial assignment count in BIO101: $INITIAL_ASSIGNMENT_COUNT"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Copy the research paper assignment reference (real data) to accessible location
cp /workspace/data/research_paper_assignment.txt /home/ga/Documents/course_materials/ 2>/dev/null || true
chown -R ga:ga /home/ga/Documents

# Ensure Firefox is running and pointed at BIO101
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/portal/site/$TARGET_SITE' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
else
    # Navigate existing Firefox to BIO101
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/portal/site/$TARGET_SITE'" 2>/dev/null || true
    sleep 3
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Sakai\|BIO" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Create Assignment Setup Complete ==="
