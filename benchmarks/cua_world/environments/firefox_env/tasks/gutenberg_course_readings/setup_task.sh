#!/bin/bash
# setup_task.sh - Pre-task hook for gutenberg_course_readings

set -e
echo "=== Setting up Gutenberg Course Readings Task ==="

# 1. Record task start time for anti-gaming (file freshness checks)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# 2. Clean previous run artifacts
# Ensure the target directory does not exist so the agent must create it
if [ -d "/home/ga/Documents/CourseTexts" ]; then
    echo "Cleaning up existing CourseTexts directory..."
    rm -rf "/home/ga/Documents/CourseTexts"
fi
# Ensure parent directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 3. Prepare Firefox
# Kill any existing instances to ensure clean database state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

# Find Firefox profile path (handles both standard and Snap installs)
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -f "$candidate/places.sqlite" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

# If no profile found (unlikely in this env), define default path
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
fi
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

# Record initial bookmark count
PLACES_DB="$PROFILE_DIR/places.sqlite"
if [ -f "$PLACES_DB" ]; then
    # Copy DB to avoid locks
    cp "$PLACES_DB" /tmp/places_baseline.sqlite 2>/dev/null || true
    INITIAL_BOOKMARKS=$(sqlite3 /tmp/places_baseline.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    rm -f /tmp/places_baseline.sqlite
else
    INITIAL_BOOKMARKS=0
fi
echo "$INITIAL_BOOKMARKS" > /tmp/initial_bookmark_count

# 4. Launch Firefox
# Start with a blank page or Gutenberg homepage to ensure it's ready
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'about:blank' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" > /dev/null; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="