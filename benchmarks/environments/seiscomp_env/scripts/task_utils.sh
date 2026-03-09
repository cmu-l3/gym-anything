#!/bin/bash
# Shared utilities for SeisComP tasks

export SEISCOMP_ROOT=/home/ga/seiscomp
export PATH="$SEISCOMP_ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$SEISCOMP_ROOT/lib:$LD_LIBRARY_PATH"
export PYTHONPATH="$SEISCOMP_ROOT/lib/python:$PYTHONPATH"
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Wait for a window matching a pattern to appear
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-60}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            echo "Window '$pattern' found"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARN: Window '$pattern' not found after ${timeout}s"
    return 1
}

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Query the SeisComP database
seiscomp_db_query() {
    local query="$1"
    mysql -u sysop -psysop seiscomp -N -e "$query" 2>/dev/null
}

# Check if scmaster is running
ensure_scmaster_running() {
    local running=0
    if su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
        LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
        seiscomp status scmaster 2>/dev/null" | grep -q "is running"; then
        running=1
    fi

    if [ $running -eq 0 ]; then
        echo "Starting scmaster..."
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp start scmaster" 2>/dev/null || true
        sleep 3
    fi
}

# Kill all instances of a SeisComP GUI application
kill_seiscomp_gui() {
    local app_name="$1"
    # Only kill the specific SeisComP binary, not scripts containing the app name
    pkill -f "$SEISCOMP_ROOT/bin/$app_name" 2>/dev/null || true
    sleep 1
}

# Launch a SeisComP GUI application as user ga
launch_seiscomp_gui() {
    local app_name="$1"
    shift
    local args="$@"

    setsid su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority \
        SEISCOMP_ROOT=$SEISCOMP_ROOT \
        PATH=$SEISCOMP_ROOT/bin:\$PATH \
        LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
        PYTHONPATH=$SEISCOMP_ROOT/lib/python:\$PYTHONPATH \
        $SEISCOMP_ROOT/bin/$app_name $args" > /tmp/${app_name}.log 2>&1 &
}

# Focus and maximize a window
focus_and_maximize() {
    local pattern="$1"
    local wid
    wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "$pattern" | head -1 | awk '{print $1}')
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -a "$wid"
        DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz
        echo "Window focused and maximized: $wid"
    else
        echo "WARN: Could not find window matching '$pattern'"
    fi
}

# Dismiss common dialogs with Escape key
dismiss_dialogs() {
    local count="${1:-3}"
    for i in $(seq 1 $count); do
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 0.5
    done
}
