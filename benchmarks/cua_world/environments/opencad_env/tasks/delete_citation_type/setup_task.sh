#!/bin/bash
echo "=== Setting up delete_citation_type task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure the target citation type exists
# We inject it to guarantee the starting state
TARGET_TYPE="Unsecured Excavation"

# check if it exists
EXISTS=$(opencad_db_query "SELECT count(*) FROM citation_types WHERE citation_type='$TARGET_TYPE'")

if [ "$EXISTS" -eq "0" ]; then
    echo "Injecting target citation type: $TARGET_TYPE"
    opencad_db_query "INSERT INTO citation_types (citation_type) VALUES ('$TARGET_TYPE')"
else
    echo "Target citation type already exists."
fi

# 2. Ensure there are other types (distractors/safety check)
# This ensures valid verification that the user didn't just truncate the table
opencad_db_query "INSERT IGNORE INTO citation_types (citation_type) VALUES ('Speeding'), ('Parking Violation'), ('Reckless Driving')"

# 3. Record initial state
INITIAL_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM citation_types")
# Save to a temp file accessible by export script
echo "$INITIAL_COUNT" | sudo tee /tmp/initial_citation_count > /dev/null
sudo chmod 666 /tmp/initial_citation_count

echo "Initial citation count: $INITIAL_COUNT"

# 4. Prepare Browser
# Remove Firefox profile locks and relaunch to ensuring clean state
rm -f /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

echo "Starting Firefox..."
DISPLAY=:1 firefox "http://localhost/index.php" &
sleep 10

# Dismiss Firefox popups/restore session dialogs
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# 5. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="