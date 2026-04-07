#!/bin/bash
set -e
echo "=== Setting up delete_dive task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure the dive log file exists and is valid
DIVE_FILE="/home/ga/Documents/dives.ssrf"
mkdir -p /home/ga/Documents

# Always restore fresh copy to ensure clean state
if [ -f /opt/subsurface_data/SampleDivesV2.ssrf ]; then
    cp /opt/subsurface_data/SampleDivesV2.ssrf "$DIVE_FILE"
else
    echo "ERROR: Original sample data not found."
    exit 1
fi
chown ga:ga "$DIVE_FILE"
chmod 644 "$DIVE_FILE"

# Record initial dive count using xmlstarlet
INITIAL_COUNT=$(xmlstarlet sel -t -v "count(//dive)" "$DIVE_FILE" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_dive_count.txt
echo "Initial dive count: $INITIAL_COUNT"

if [ "$INITIAL_COUNT" -lt 2 ]; then
    echo "ERROR: Not enough dives in sample file (found $INITIAL_COUNT, need at least 2)"
    exit 1
fi

# Identify the last dive (most recent by date+time) and record its details
# Subsurface stores date like "2011-09-29" and time like "10:30:00"
LAST_DIVE_DATETIME=$(xmlstarlet sel -t -m "//dive" -v "concat(@date, 'T', @time)" -n "$DIVE_FILE" 2>/dev/null | sort | tail -1)
LAST_DATE=$(echo "$LAST_DIVE_DATETIME" | cut -dT -f1)
LAST_TIME=$(echo "$LAST_DIVE_DATETIME" | cut -dT -f2)

echo "$LAST_DATE" > /tmp/target_dive_date.txt
echo "$LAST_TIME" > /tmp/target_dive_time.txt
echo "Target dive to delete: Date=$LAST_DATE, Time=$LAST_TIME"

# Kill any existing Subsurface instances
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Ensure X server is accessible
xhost +local: 2>/dev/null || true

# Launch Subsurface with the dive file
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid subsurface '$DIVE_FILE' >/tmp/subsurface_task.log 2>&1 &"

# Wait for Subsurface window
WINDOW_FOUND=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "subsurface"; then
        WINDOW_FOUND=true
        echo "Subsurface window detected after ${i}s"
        break
    fi
    sleep 1
done

# Dismiss any dialogs
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Maximize and focus Subsurface
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="