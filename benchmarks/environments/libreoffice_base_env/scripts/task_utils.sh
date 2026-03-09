#!/bin/bash
# Shared utilities for all LibreOffice Base tasks.
# Source this file: source /workspace/scripts/task_utils.sh

# --- Process management ---

kill_libreoffice() {
    echo "Killing any running LibreOffice instances..."
    pkill -f "soffice" 2>/dev/null || true
    pkill -f "soffice.bin" 2>/dev/null || true
    sleep 2
    pkill -9 -f "soffice" 2>/dev/null || true
    pkill -9 -f "soffice.bin" 2>/dev/null || true
    sleep 1
    echo "LibreOffice stopped."
}

is_libreoffice_running() {
    pgrep -f "soffice" > /dev/null 2>&1
}

# --- Launch LibreOffice Base with the Chinook ODB ---

launch_libreoffice_base() {
    local odb_path="${1:-/home/ga/chinook.odb}"
    echo "Launching LibreOffice Base with: $odb_path"
    su - ga -c "DISPLAY=:1 soffice --nofirststartwizard --norestore '$odb_path' &"
}

# --- Wait for LibreOffice Base window to appear ---

wait_for_libreoffice_base() {
    local timeout="${1:-45}"
    local elapsed=0
    echo "Waiting for LibreOffice Base window (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        # Look for Base window (matches ODB filename or class)
        WID=$(DISPLAY=:1 xdotool search --name "chinook" 2>/dev/null | head -1)
        if [ -n "$WID" ]; then
            echo "LibreOffice Base window found after ${elapsed}s (WID: $WID)"
            return 0
        fi
        WID=$(DISPLAY=:1 xdotool search --class "soffice" 2>/dev/null | head -1)
        if [ -n "$WID" ]; then
            echo "LibreOffice window found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "WARNING: LibreOffice Base window not found within ${timeout}s"
    return 1
}

# --- Dismiss first-run / HSQLDB migration dialogs ---

dismiss_dialogs() {
    echo "Dismissing any LibreOffice dialogs..."
    for attempt in 1 2 3 4 5; do
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 0.4
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 0.4
    done

    # Check specifically for HSQLDB migration dialog
    for check in 1 2 3; do
        MIG=$(DISPLAY=:1 xdotool search --name "Migration" 2>/dev/null | head -1)
        if [ -n "$MIG" ]; then
            echo "Found migration dialog, dismissing with Escape..."
            DISPLAY=:1 xdotool windowfocus "$MIG" 2>/dev/null || true
            sleep 0.3
            DISPLAY=:1 xdotool key Escape 2>/dev/null || true
            sleep 1
        fi
        sleep 1
    done
    echo "Dialog dismissal complete."
}

# --- Focus and maximize the LibreOffice Base main window ---

maximize_libreoffice() {
    # Try to maximize by window title
    DISPLAY=:1 wmctrl -r "chinook" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 0.5
    # Fallback: maximize active window
    DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 0.5
}

# --- Restore a fresh copy of chinook.odb ---

restore_chinook_odb() {
    echo "Restoring fresh copy of chinook.odb..."
    cp /opt/libreoffice_base_samples/chinook.odb /home/ga/chinook.odb
    chown ga:ga /home/ga/chinook.odb
    chmod 644 /home/ga/chinook.odb
    echo "chinook.odb restored."
}

# --- Take a screenshot ---

take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# --- Full setup sequence used by most tasks ---
# Kills LibreOffice, restores ODB, launches fresh, waits for window,
# dismisses dialogs, and maximizes.

setup_libreoffice_base_task() {
    local odb_path="${1:-/home/ga/chinook.odb}"

    kill_libreoffice
    restore_chinook_odb
    launch_libreoffice_base "$odb_path"
    wait_for_libreoffice_base 45
    sleep 3  # Give app time to fully render
    dismiss_dialogs
    sleep 1
    maximize_libreoffice
    sleep 1
}
