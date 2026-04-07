#!/bin/bash
echo "=== Setting up Trailer Automation task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions in case task_utils is missing
kill_ardour() {
    pkill -f "/usr/lib/ardour" 2>/dev/null || true
    sleep 2
    pkill -9 -f "/usr/lib/ardour" 2>/dev/null || true
    sleep 1
}

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

# Kill any existing Ardour instances
kill_ardour

# Create backup of clean session on first run to allow reset
if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
fi

# Restore clean session to ensure fresh state
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
fi

# Ensure audio samples exist
if [ ! -f /home/ga/Audio/samples/moonlight_sonata.wav ]; then
    echo "WARNING: moonlight_sonata.wav not found, generating fallback..."
    mkdir -p /home/ga/Audio/samples
    sox -n -r 44100 -c 2 /home/ga/Audio/samples/moonlight_sonata.wav synth 30 sine 440:880 fade h 0.5 30 0.5 2>/dev/null || true
fi

# Record initial automation state (should be empty/Off)
if [ -f "$SESSION_FILE" ]; then
    GAIN_AUTO_COUNT=$(grep -c 'automation-id="parameter-16"' "$SESSION_FILE" 2>/dev/null || echo "0")
    echo "Initial gain automation entries: $GAIN_AUTO_COUNT" > /tmp/initial_automation_state.txt
fi

# Launch Ardour with session
echo "Launching Ardour..."
su - ga -c "DISPLAY=:1 setsid ardour8 '$SESSION_FILE' > /tmp/ardour_task.log 2>&1 &" 2>/dev/null || \
su - ga -c "DISPLAY=:1 setsid ardour '$SESSION_FILE' > /tmp/ardour_task.log 2>&1 &" 2>/dev/null || true

# Wait for Ardour window
sleep 8
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "MyProject"; then
        break
    fi
    sleep 2
done

# Dismiss any popup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Check if any region exists in the session XML; if not, import the audio file
REGION_COUNT=$(grep -c '<Region' "$SESSION_FILE" 2>/dev/null || echo "0")
if [ "$REGION_COUNT" -lt 1 ]; then
    echo "Importing audio into session..."
    
    # Focus main window
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
    fi
    
    # Use the Import dialog (Ctrl+I)
    DISPLAY=:1 xdotool key ctrl+i 2>/dev/null || true
    sleep 3
    
    IMPORT_WID=$(DISPLAY=:1 xdotool search --name "Import" 2>/dev/null | head -1)
    if [ -n "$IMPORT_WID" ]; then
        # Open location bar in file chooser (Ctrl+L)
        DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
        sleep 1
        # Type path
        DISPLAY=:1 xdotool type "/home/ga/Audio/samples/moonlight_sonata.wav" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 2
        # Press Return to confirm import
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 5
    fi
fi

# Focus and maximize the main window
WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
fi
sleep 2

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Trailer Automation task setup complete ==="