#!/bin/bash
set -e
echo "=== Setting up configure_quick_copy_indigo task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Cleanup previous output
rm -f /home/ga/Documents/brown_citation.txt

# Get Jurism database path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi

# Kill Jurism to safely modify DB and prefs
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 1. Inject legal references (Direct SQLite injection)
echo "Injecting legal references..."
python3 /workspace/utils/inject_references.py "$DB_PATH"

# 2. Force Quick Copy preference to APA (incorrect state)
# We use user.js to enforce this preference on startup.
# This ensures the agent starts with the WRONG setting and must change it.
PROFILE_DIR=""
for dir in /home/ga/.jurism/jurism/*.default /home/ga/.zotero/zotero/*.default; do
    if [ -d "$dir" ]; then
        PROFILE_DIR="$dir"
        break
    fi
done

if [ -n "$PROFILE_DIR" ]; then
    echo "Configuring profile at $PROFILE_DIR"
    
    # Create or append to user.js to force APA style on startup
    # Style ID for APA 7th edition
    cat >> "$PROFILE_DIR/user.js" << 'EOF'
user_pref("extensions.zotero.export.quickCopy.setting", "bibliography=http://www.zotero.org/styles/apa");
EOF
    chown ga:ga "$PROFILE_DIR/user.js"
    echo "Forced APA style in user.js"
else
    echo "WARNING: Could not find profile directory"
fi

# Relaunch Jurism to pick up new items and settings
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism and dismiss alerts
wait_and_dismiss_jurism_alerts 45

# Maximize window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Task: Configure Quick Copy to 'JM Indigo (Law Review)' and export citation for Brown v. Board of Education."