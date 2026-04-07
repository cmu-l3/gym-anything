#!/bin/bash
set -e
echo "=== Setting up platform_readiness_certification task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
export DISPLAY=:1

# 1. Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Desktop/platform_readiness_report.txt 2>/dev/null || true

# 3. Record initial log state for delta analysis
OPENICE_LOG="/home/ga/openice/logs/openice.log"
# Ensure the log directory exists
mkdir -p /home/ga/openice/logs
# If log doesn't exist, create it so we have a baseline
touch "$OPENICE_LOG"
# Record size
wc -c < "$OPENICE_LOG" > /tmp/initial_log_size.txt

# 4. Record initial window state
DISPLAY=:1 wmctrl -l 2>/dev/null > /tmp/initial_windows.txt || true
DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l > /tmp/initial_window_count.txt || echo "0" > /tmp/initial_window_count.txt

# 5. Ensure OpenICE is running
if ! pgrep -f "java.*demo-apps\|gradlew.*demo-apps" > /dev/null 2>&1; then
    echo "Starting OpenICE..."
    # Use the supervisor script provided by the environment
    if [ -f "/home/ga/openice/launch_supervisor.sh" ]; then
        su - ga -c "cd /home/ga/openice && DISPLAY=:1 ./launch_supervisor.sh" &
    else
        # Fallback launch
        su - ga -c "cd /opt/openice/mdpnp && ./gradlew :interop-lab:demo-apps:run --no-daemon" > "$OPENICE_LOG" 2>&1 &
    fi
    
    # Wait for window (can take a while for Java/Gradle)
    echo "Waiting for OpenICE window..."
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "openice|supervisor|demo|ice" > /dev/null 2>&1; then
            echo "OpenICE window detected"
            break
        fi
        sleep 2
    done
fi

# 6. Maximize and focus window
sleep 5
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "openice|supervisor|demo|ice" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# 7. Update initial state records (in case startup created logs/windows)
wc -c < "$OPENICE_LOG" > /tmp/initial_log_size_post_setup.txt
DISPLAY=:1 wmctrl -l 2>/dev/null > /tmp/initial_windows_post_setup.txt || true

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Start time: $(cat /tmp/task_start_time.txt)"
echo "Initial log size: $(cat /tmp/initial_log_size_post_setup.txt)"