#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero harmlessly

echo "=== Setting up gitflow_workflow_diagram task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any existing output files
rm -f /home/ga/Desktop/gitflow.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/gitflow.png 2>/dev/null || true

# Create the event log file
cat > /home/ga/Desktop/git_event_log.txt << 'LOGEOF'
Project Phoenix - Git Operation Log
===================================
Time flows from top to bottom (earliest to latest).

1. [Develop] Initial commit (Start of project)
2. [Feature] Branch 'auth-module' created from [Develop]
3. [Feature] Commit "Add login form"
4. [Develop] Merge branch 'auth-module' into [Develop]
5. [Release] Branch 'release/v1.0' created from [Develop]
6. [Release] Commit "Bump version number to 1.0"
7. [Main] Merge branch 'release/v1.0' into [Main] -> TAG: v1.0
8. [Develop] Merge branch 'release/v1.0' into [Develop] (Back-merge)
9. [Hotfix] Branch 'hotfix/v1.0.1' created from [Main]
10. [Main] Merge branch 'hotfix/v1.0.1' into [Main] -> TAG: v1.0.1
11. [Develop] Merge branch 'hotfix/v1.0.1' into [Develop] (Back-merge)

INSTRUCTIONS:
- Visualize this flow using horizontal swimlanes.
- Lanes: Main, Hotfix, Release, Develop, Feature.
- Use circles for commits and arrows for flow.
LOGEOF

chown ga:ga /home/ga/Desktop/git_event_log.txt
chmod 644 /home/ga/Desktop/git_event_log.txt

# Record start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Launch draw.io (startup dialog will appear)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_gitflow.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for UI to fully load
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Verify draw.io is running
if pgrep -f "drawio" > /dev/null; then
    echo "draw.io is running"
else
    echo "Warning: draw.io may not have started properly"
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="