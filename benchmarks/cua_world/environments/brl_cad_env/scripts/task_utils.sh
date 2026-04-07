#!/bin/bash
# Shared utilities for BRL-CAD tasks

# Load BRL-CAD paths
BRLCAD_ROOT=$(cat /tmp/brlcad_root.txt 2>/dev/null || echo "/usr/brlcad")
export PATH="${BRLCAD_ROOT}/bin:$PATH"
export LD_LIBRARY_PATH="${BRLCAD_ROOT}/lib:$LD_LIBRARY_PATH"

# Kill any running MGED instance (and its xterm host)
kill_mged() {
    pkill -f "${BRLCAD_ROOT}/bin/mged" 2>/dev/null || pkill -f "mged" 2>/dev/null || true
    pkill -f "xterm.*MGED" 2>/dev/null || true
    sleep 2
}

# Write MGED init commands to .mgedrc
# These execute automatically when MGED starts
# Usage: write_mgedrc "e all.g" "ae 35 25" "autoview"
write_mgedrc() {
    cat > /home/ga/.mgedrc << 'HEADER'
# Auto-generated MGED init commands for task
HEADER
    # Build after-script with all commands
    echo 'after 2000 {' >> /home/ga/.mgedrc
    for cmd in "$@"; do
        echo "    catch {$cmd}" >> /home/ga/.mgedrc
    done
    echo '}' >> /home/ga/.mgedrc
    chown ga:ga /home/ga/.mgedrc
}

# Launch MGED with a .g database file via launcher script
# Usage: launch_mged /path/to/file.g
launch_mged() {
    local file="${1:-}"
    if [ -n "$file" ]; then
        su - ga -c "setsid /usr/local/bin/launch_mged.sh '$file' > /tmp/mged_task.log 2>&1 &"
    else
        su - ga -c "setsid /usr/local/bin/launch_mged.sh > /tmp/mged_task.log 2>&1 &"
    fi
}

# Wait for MGED window to appear (looks for Graphics or Command Window)
wait_for_mged() {
    local timeout="${1:-45}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "Graphics Window\|Command Window"; then
            echo "MGED window detected"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: MGED window not detected after ${timeout}s"
    return 1
}

# Position MGED windows side-by-side (Command left, Graphics right)
position_mged_windows() {
    sleep 1
    # Minimize the xterm (it's just the TTY host)
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name MGED_Terminal windowminimize 2>/dev/null || true
    sleep 0.5
    # Remove maximized state first
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "Command Window" -b remove,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "Graphics Window" -b remove,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 0.3
    # Position Command Window on left half
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "Command Window" -e 0,0,0,960,1080 2>/dev/null || true
    sleep 0.3
    # Position Graphics Window on right half
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "Graphics Window" -e 0,960,0,960,1080 2>/dev/null || true
    sleep 0.5
}

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || true
}
