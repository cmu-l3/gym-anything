#!/bin/bash
echo "=== Setting up change_citation_style task ==="
source /workspace/scripts/task_utils.sh

# Find the Jurism profile directory
PROFILE_DIR=""
for profile_base in /home/ga/.jurism/jurism /home/ga/.zotero/zotero; do
    found=$(find "$profile_base" -maxdepth 1 -type d -name "*.default" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        PROFILE_DIR="$found"
        break
    fi
done

if [ -n "$PROFILE_DIR" ]; then
    echo "Profile directory: $PROFILE_DIR"
    # Record current citation style for verification
    CURRENT_STYLE=$(grep "quickCopy\|lastStyle" "$PROFILE_DIR/prefs.js" 2>/dev/null | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "none")
    echo "${CURRENT_STYLE:-none}" > /tmp/initial_citation_style
    echo "Current citation style pref: $CURRENT_STYLE"

    # Normalize start state: set Quick Copy to Chicago (non-OSCOLA) via user.js.
    # user.js is applied by Jurism on every startup, overriding prefs.js values.
    cat > "$PROFILE_DIR/user.js" << 'USERJS'
// Force Quick Copy style to Chicago so agent must change it to OSCOLA
user_pref("extensions.zotero.export.quickCopyMode", "bibliography");
user_pref("extensions.zotero.export.quickCopySetting", "http://www.zotero.org/styles/chicago-author-date");
USERJS
    chown ga:ga "$PROFILE_DIR/user.js" 2>/dev/null || true
    echo "Wrote user.js: Chicago set as Quick Copy start style"
else
    echo "none" > /tmp/initial_citation_style
    echo "WARNING: Jurism profile directory not found"
fi

# Record start timestamp
date +%s > /tmp/task_start_timestamp

# Stop Jurism so user.js takes effect on next launch
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Relaunch Jurism (user.js will apply Chicago as Quick Copy on startup)
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_restart.log 2>&1 &'
sleep 5

# Wait for Jurism to load and dismiss any in-app alert dialogs
wait_and_dismiss_jurism_alerts 45

DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take screenshot to verify state
DISPLAY=:1 import -window root /tmp/style_task_start.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/style_task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Start style: $(cat /tmp/initial_citation_style)"
echo "Task: Change Quick Copy style to OSCOLA (Edit > Preferences > Cite)"
