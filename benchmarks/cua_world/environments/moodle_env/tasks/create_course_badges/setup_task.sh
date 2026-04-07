#!/bin/bash
# Setup script for Create Course Badges task

echo "=== Setting up Create Course Badges Task ==="

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

# 1. Prepare Badge Images
echo "Generating badge images..."
mkdir -p /home/ga/badge_images
python3 -c "
import struct, zlib

def create_png(filename, r, g, b, size=200):
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    raw = b''
    for y in range(size):
        raw += b'\x00' + bytes([r, g, b]) * size
    with open(filename, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)))
        f.write(chunk(b'IDAT', zlib.compress(raw)))
        f.write(chunk(b'IEND', b''))

create_png('/home/ga/badge_images/safety_badge.png', 34, 139, 34)
create_png('/home/ga/badge_images/completion_badge.png', 30, 80, 180)
"
chown -R ga:ga /home/ga/badge_images
echo "Badge images created at /home/ga/badge_images/"

# 2. Configure Course (BIO101)
echo "Configuring BIO101..."
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')

if [ -z "$COURSE_ID" ]; then
    echo "ERROR: BIO101 course not found. Creating fallback..."
    # Fallback creation logic if course is missing (safety net)
    # ... (omitted for brevity, relying on standard env setup)
    exit 1
fi

# Enable completion tracking for the course (required for course completion criteria)
moodle_query "UPDATE mdl_course SET enablecompletion=1 WHERE id=$COURSE_ID"
echo "Enabled completion tracking for course ID $COURSE_ID"

# 3. Record Initial State
INITIAL_BADGE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_badge WHERE courseid=$COURSE_ID" | tr -d '[:space:]')
echo "$INITIAL_BADGE_COUNT" > /tmp/initial_badge_count
echo "Initial badge count in BIO101: $INITIAL_BADGE_COUNT"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# 4. Launch Application
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