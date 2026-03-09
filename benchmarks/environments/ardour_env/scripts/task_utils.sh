#!/bin/bash
# Shared utilities for Ardour tasks

# Get the Ardour binary name
get_ardour_bin() {
    if [ -f /tmp/ardour_bin_name ]; then
        cat /tmp/ardour_bin_name
    else
        for v in 8 7 6; do
            if command -v "ardour${v}" &>/dev/null; then
                echo "ardour${v}"
                return
            fi
        done
        echo "ardour"
    fi
}

# Get Ardour version number
get_ardour_version() {
    if [ -f /tmp/ardour_version ]; then
        cat /tmp/ardour_version
    else
        echo "8"
    fi
}

# Wait for a window matching a pattern to appear
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        WID=$(DISPLAY=:1 xdotool search --name "$pattern" 2>/dev/null | head -1)
        if [ -n "$WID" ]; then
            echo "$WID"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo ""
    return 1
}

# Wait for a process to appear
wait_for_process() {
    local pattern="$1"
    local timeout="${2:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "$pattern" > /dev/null 2>&1; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Kill all Ardour processes
kill_ardour() {
    # Use /usr/lib/ardour pattern to avoid killing scripts named *ardour*
    pkill -f "/usr/lib/ardour" 2>/dev/null || true
    sleep 2
    pkill -9 -f "/usr/lib/ardour" 2>/dev/null || true
    sleep 1
}

# Focus a window by ID
focus_window() {
    local wid="$1"
    DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
    DISPLAY=:1 xdotool windowactivate "$wid" 2>/dev/null || true
}

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Handle Audio/MIDI Setup dialog if it appears.
# Uses window-relative coordinates so it works regardless of where the dialog is placed.
handle_audio_setup_dialog() {
    echo "Checking for Audio/MIDI Setup dialog..."
    local setup_wid
    setup_wid=$(DISPLAY=:1 xdotool search --name "Audio/MIDI Setup" 2>/dev/null | head -1)
    if [ -z "$setup_wid" ]; then
        echo "No Audio/MIDI Setup dialog found"
        return 0
    fi

    echo "Audio/MIDI Setup dialog detected - configuring Dummy backend..."
    DISPLAY=:1 wmctrl -a "Audio/MIDI Setup" 2>/dev/null || true
    sleep 1

    # Get window position and size for relative coordinates
    local geom wx wy ww wh
    geom=$(DISPLAY=:1 xdotool getwindowgeometry "$setup_wid" 2>/dev/null || echo "")
    wx=$(echo "$geom" | grep -oP 'Position: \K\d+')
    wy=$(echo "$geom" | grep -oP ',\K\d+(?= )')
    ww=$(echo "$geom" | grep -oP 'Geometry: \K\d+')
    wh=$(echo "$geom" | grep -oP 'x\K\d+$')

    if [ -z "$wx" ] || [ -z "$wy" ]; then
        echo "WARNING: Could not get Audio/MIDI Setup window geometry"
        return 1
    fi
    echo "Dialog geometry: pos($wx,$wy) size(${ww}x${wh})"

    # Audio System dropdown: ~55% from left edge, ~35px from top (first row)
    local dx=$((wx + ww * 55 / 100))
    local dy=$((wy + 35))
    echo "Clicking Audio System dropdown at ($dx,$dy)..."
    DISPLAY=:1 xdotool mousemove "$dx" "$dy" click 1 2>/dev/null || true
    sleep 2

    # Select "None (Dummy)" - 3rd item in dropdown list (ALSA, JACK, Dummy)
    local dy_dummy=$((dy + 55))
    echo "Selecting Dummy backend at ($dx,$dy_dummy)..."
    DISPLAY=:1 xdotool mousemove "$dx" "$dy_dummy" click 1 2>/dev/null || true
    sleep 2

    # Click Start button: ~78% from left edge, same row as Audio System
    local sx=$((wx + ww * 78 / 100))
    local sy=$((wy + 35))
    echo "Clicking Start at ($sx,$sy)..."
    for attempt in $(seq 1 3); do
        DISPLAY=:1 xdotool mousemove "$sx" "$sy" click 1 2>/dev/null || true
        sleep 3
    done

    echo "Audio/MIDI Setup dialog handled"
}

# Launch Ardour with a session and wait for it to be ready
launch_ardour_session() {
    local session_path="$1"
    local ardour_bin
    ardour_bin=$(get_ardour_bin)

    echo "Launching Ardour with session: $session_path"
    su - ga -c "DISPLAY=:1 setsid $ardour_bin '$session_path' > /tmp/ardour_task.log 2>&1 &"

    # First wait for any Ardour window to appear (could be Audio/MIDI Setup or session)
    echo "Waiting for Ardour window..."
    local any_window=0
    for i in $(seq 1 30); do
        WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
        if echo "$WINDOWS" | grep -qi "ardour\|audio.*midi\|MyProject"; then
            echo "Ardour window appeared after $((i*2))s"
            any_window=1
            break
        fi
        sleep 2
    done

    if [ "$any_window" -eq 0 ]; then
        echo "WARNING: No Ardour window appeared within 60s"
        return 1
    fi

    sleep 3

    # Handle Audio/MIDI Setup dialog if it appeared instead of the session
    handle_audio_setup_dialog

    # Now wait for session window (title includes session name)
    echo "Waiting for session to load..."
    local session_loaded=0
    for i in $(seq 1 60); do
        WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
        if echo "$WINDOWS" | grep -q "MyProject"; then
            echo "Session loaded after $((i*2))s"
            session_loaded=1
            break
        fi
        sleep 2
    done

    # Check for Audio/MIDI Setup dialog again (can reappear after engine start)
    handle_audio_setup_dialog

    if [ "$session_loaded" -eq 1 ]; then
        sleep 3
        # Focus and maximize the main Ardour window
        local wid
        wid=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
        if [ -n "$wid" ]; then
            focus_window "$wid"
            DISPLAY=:1 wmctrl -r "MyProject" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        fi
        return 0
    else
        echo "WARNING: Ardour session did not load within timeout"
        return 1
    fi
}
