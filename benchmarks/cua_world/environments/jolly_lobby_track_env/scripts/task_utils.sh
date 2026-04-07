#!/bin/bash
# task_utils.sh — Shared utilities for Jolly Lobby Track tasks

# ============================================================
# Screenshot function
# ============================================================
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# ============================================================
# Find Lobby Track executable
# ============================================================
find_lobbytrack_exe() {
    local exe
    exe=$(find /home/ga/.wine/drive_c -iname "LobbyTrack*.exe" -not -iname "*Setup*" -not -iname "*uninstall*" 2>/dev/null | head -1)
    if [ -z "$exe" ]; then
        exe=$(find /home/ga/.wine/drive_c -iname "Lobby*.exe" -not -iname "*Setup*" -not -iname "*uninstall*" 2>/dev/null | head -1)
    fi
    echo "$exe" >&2
    echo "$exe"
}

# ============================================================
# Wait for Lobby Track window to appear
# ============================================================
wait_for_lobbytrack_window() {
    local timeout="${1:-60}"
    echo "Waiting for Lobby Track window (up to ${timeout}s)..." >&2
    for i in $(seq 1 "$timeout"); do
        WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "lobby\|jolly\|visitor\|track" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            echo "Lobby Track window found: $WID (${i}s)" >&2
            echo "$WID"
            return 0
        fi
        sleep 1
    done
    echo "WARNING: Lobby Track window not found after ${timeout}s" >&2
    DISPLAY=:1 wmctrl -l 2>/dev/null >&2 || true
    return 1
}

# ============================================================
# Launch Lobby Track and wait for window
# ============================================================
launch_lobbytrack() {
    echo "Launching Lobby Track..." >&2

    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        echo "Launch attempt $attempt of $max_attempts..." >&2

        # Kill any existing instances
        pkill -f "LobbyTrack" 2>/dev/null || true
        pkill -f "Lobby" 2>/dev/null || true
        pkill -x wine 2>/dev/null || true
        sleep 2
        # Ensure wineserver is stopped for clean start
        su - ga -c "wineserver -k" 2>/dev/null || true
        sleep 1

        # Launch with setsid
        su - ga -c "setsid /home/ga/launch_lobbytrack.sh > /tmp/lobbytrack_task.log 2>&1 &"

        # Wait for process to appear (up to 30s)
        echo "Waiting for Lobby Track process (up to 30s)..." >&2
        local proc_found=0
        for i in $(seq 1 15); do
            sleep 2
            if pgrep -f "LobbyTrack\|Lobby.*Track" > /dev/null 2>&1; then
                echo "Lobby Track process detected (${i}x2s)" >&2
                proc_found=1
                break
            fi
            # Also check wine processes
            if pgrep -f "wine.*[Ll]obby" > /dev/null 2>&1; then
                echo "Wine/Lobby process detected (${i}x2s)" >&2
                proc_found=1
                break
            fi
        done

        if [ $proc_found -eq 0 ]; then
            echo "  Process not detected on attempt $attempt." >&2
            attempt=$((attempt + 1))
            continue
        fi

        # Wait for window (up to 60s)
        local wid
        wid=$(wait_for_lobbytrack_window 60) || true

        if [ -n "$wid" ]; then
            # Maximize window
            DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
            sleep 2
            # Dismiss any startup dialogs
            dismiss_startup_dialogs
            echo "Current windows:" >&2
            DISPLAY=:1 wmctrl -l 2>/dev/null >&2 || true
            return 0
        fi

        echo "  Window not found on attempt $attempt." >&2
        attempt=$((attempt + 1))
    done

    echo "WARNING: All $max_attempts launch attempts failed for Lobby Track." >&2
    DISPLAY=:1 wmctrl -l 2>/dev/null >&2 || true
    echo "Wine processes:" >&2
    ps aux | grep -i "wine\|lobby" | grep -v grep >&2 || true
    echo "Current windows:" >&2
    DISPLAY=:1 wmctrl -l 2>/dev/null >&2 || true
}

# ============================================================
# Dismiss startup dialogs (first-run, license, tips, etc.)
# ============================================================
dismiss_startup_dialogs() {
    echo "Dismissing startup dialogs..." >&2
    # Try pressing Enter to dismiss "OK" buttons
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" 2>/dev/null || true
    sleep 2
    # Try pressing Escape to dismiss optional dialogs
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Escape" 2>/dev/null || true
    sleep 1
    # Another Enter in case there's a second dialog
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" 2>/dev/null || true
    sleep 1
    # One more Escape
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Escape" 2>/dev/null || true
    sleep 1
}

# ============================================================
# Ensure Lobby Track is running
# ============================================================
ensure_lobbytrack_running() {
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "lobby\|jolly\|visitor\|track" > /dev/null 2>&1; then
        echo "Lobby Track is already running." >&2
        return 0
    fi
    launch_lobbytrack
}

# ============================================================
# Record task start timestamp
# ============================================================
record_start_time() {
    local task_name="$1"
    date +%s > "/tmp/${task_name}_start_time"
    echo "Task $task_name start time: $(date)" >&2
}
