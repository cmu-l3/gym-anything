#!/bin/bash
# setup_task.sh - Pre-task hook for pdb_protein_structure_research

set -e
echo "=== Setting up PDB Research Task ==="

# 1. Kill Firefox to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 2. Record Task Start Time
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 3. Clean up previous artifacts
rm -f /home/ga/Documents/protein_structures.json 2>/dev/null || true
# Clean downloads of potential target files
find /home/ga/Downloads -name "*4hhb*" -delete 2>/dev/null || true
find /home/ga/Downloads -name "*4HHB*" -delete 2>/dev/null || true

# 4. Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Downloads

# 5. Record initial bookmark state
# Find profile
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -f "$candidate/places.sqlite" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done
# Fallback search
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "/home/ga/.mozilla/firefox/default.profile")
fi
echo "$PROFILE_DIR" > /tmp/firefox_profile_path

if [ -f "$PROFILE_DIR/places.sqlite" ]; then
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_initial.sqlite
    # Record initial bookmark count
    sqlite3 /tmp/places_initial.sqlite "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" > /tmp/initial_bookmark_count 2>/dev/null || echo "0" > /tmp/initial_bookmark_count
else
    echo "0" > /tmp/initial_bookmark_count
fi

# 6. Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote > /tmp/firefox.log 2>&1 &"

# Wait for window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" > /dev/null; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# 7. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="