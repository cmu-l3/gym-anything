#!/bin/bash
# Shared utilities for GCompris tasks

# Determine the correct GCompris binary
# gcompris-qt installs to /usr/games/ on Ubuntu
get_gcompris_bin() {
    if [ -x "/usr/games/gcompris-qt" ]; then
        echo "/usr/games/gcompris-qt"
    elif command -v gcompris-qt &> /dev/null; then
        echo "gcompris-qt"
    elif command -v gcompris &> /dev/null; then
        echo "gcompris"
    else
        echo ""
    fi
}

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# Kill all GCompris processes
kill_gcompris() {
    pkill -f "gcompris-qt" 2>/dev/null || true
    pkill -f "/usr/games/gcompris" 2>/dev/null || true
    sleep 2
}

# Launch GCompris (main menu, no specific activity)
# Note: GCompris 2.3 does NOT support --launch flag; always starts at main menu.
# Hooks run as root; use sudo -u ga to launch as the ga user with display access.
launch_gcompris() {
    local bin
    bin=$(get_gcompris_bin)
    if [ -z "$bin" ]; then
        echo "ERROR: GCompris not found"
        return 1
    fi
    # Launch as ga user; works whether script runs as root (via hook) or as ga
    if [ "$(whoami)" = "root" ]; then
        sudo -u ga DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority "$bin" -m &
    else
        DISPLAY=:1 "$bin" -m &
    fi
    # Wait for the main menu window to appear (up to 40s)
    local timeout=40
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "gcompris"; then
            echo "GCompris window ready"
            sleep 3  # Extra wait for the UI to fully render
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: GCompris window did not appear within ${timeout}s"
    return 0
}

# Maximize GCompris window
maximize_gcompris() {
    sleep 1
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "GCompris" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
}
