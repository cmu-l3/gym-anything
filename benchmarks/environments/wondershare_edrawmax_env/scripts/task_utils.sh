#!/bin/bash
# Shared utilities for Wondershare EdrawMax tasks

# Discover and return the EdrawMax binary path
get_edrawmax_bin() {
    for candidate in "/usr/bin/edrawmax" "/usr/local/bin/edrawmax"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    local found
    found=$(find /opt -name "EdrawMax" -executable -type f 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi
    echo "edrawmax"  # fallback to PATH
    return 1
}

# Kill all running EdrawMax instances gracefully then forcefully
kill_edrawmax() {
    pkill -f "EdrawMax" 2>/dev/null || true
    pkill -f "edrawmax" 2>/dev/null || true
    sleep 2
    pkill -9 -f "EdrawMax" 2>/dev/null || true
    pkill -9 -f "edrawmax" 2>/dev/null || true
    sleep 1
}

# Check if EdrawMax is running
is_edrawmax_running() {
    pgrep -f "EdrawMax" > /dev/null 2>&1 || pgrep -f "edrawmax" > /dev/null 2>&1
}

# Launch EdrawMax (optionally with a file to open)
launch_edrawmax() {
    local file="${1:-}"
    local bin
    bin=$(get_edrawmax_bin)

    if [ -n "$file" ] && [ -f "$file" ]; then
        su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority '${bin}' '${file}' &"
    else
        su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority '${bin}' &"
    fi
}

# Wait for EdrawMax window to appear
wait_for_edrawmax() {
    local timeout="${1:-90}"
    local elapsed=0

    echo "Waiting for EdrawMax to start (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if is_edrawmax_running; then
            echo "EdrawMax process found after ${elapsed}s"
            # Wait additional time for UI to fully render
            sleep 15
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: EdrawMax did not start within ${timeout}s"
    return 1
}

# Dismiss EdrawMax startup dialogs (Account Login + File Recovery)
# Must be called after wait_for_edrawmax to ensure dialogs have appeared.
# Coordinates are for 1920x1080 resolution (VG 1280x720 -> actual 1920x1080, scale 1.5x)
dismiss_edrawmax_dialogs() {
    echo "Dismissing EdrawMax startup dialogs..."

    # Wait for dialogs and UI to fully render
    sleep 5

    # Dismiss Account Login dialog: X button at VG(863,197) = actual(1294,296)
    DISPLAY=:1 xdotool mousemove 1294 296 click 1 2>/dev/null || true
    sleep 2

    # Dismiss File Recovery modal dialog window (if present as separate window)
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q "File Recovery"; then
        echo "File Recovery dialog window detected - dismissing..."
        DISPLAY=:1 xdotool mousemove 1294 327 click 1 2>/dev/null || true
        sleep 2
    fi

    # Dismiss the in-app "temporarily saved files" notification BANNER.
    # This is an embedded toolbar banner (NOT a separate window), so wmctrl cannot detect it.
    # The "Got it" button appears at approximately actual(459,267) in 1920x1080.
    echo "Dismissing in-app notification banner (Got it button)..."
    DISPLAY=:1 xdotool mousemove 459 267 click 1 2>/dev/null || true
    sleep 1
    # Second click at slightly different position for layout variations
    DISPLAY=:1 xdotool mousemove 350 204 click 1 2>/dev/null || true
    sleep 1

    # Escape key fallback
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    # Wait for banner to disappear and UI to settle
    sleep 2

    echo "Dialog dismissal complete."
}

# Maximize EdrawMax main window
maximize_edrawmax() {
    # Try multiple window title variants
    DISPLAY=:1 wmctrl -r "EdrawMax" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -r "Wondershare EdrawMax" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
}

# Take a screenshot of the desktop
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    # Use import (ImageMagick) - works better with GNOME compositor than scrot
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# Find a real EdrawMax template file from the installation
find_template() {
    local category="${1:-}"  # optional category hint (e.g., "flowchart", "mindmap")

    # First check the pre-copied templates in ~/Diagrams/
    if [ -n "$category" ]; then
        local tmpl
        tmpl=$(find /home/ga/Diagrams -iname "*${category}*" -name "*.eddx" 2>/dev/null | head -1)
        if [ -n "$tmpl" ]; then
            echo "$tmpl"
            return 0
        fi
    fi

    # Check home Diagrams dir for any eddx
    local tmpl
    tmpl=$(find /home/ga/Diagrams -name "*.eddx" 2>/dev/null | head -1)
    if [ -n "$tmpl" ]; then
        echo "$tmpl"
        return 0
    fi

    # Search in the EdrawMax installation directory
    if [ -n "$category" ]; then
        tmpl=$(find /opt -iname "*${category}*" -name "*.eddx" 2>/dev/null | head -1)
        if [ -n "$tmpl" ]; then
            echo "$tmpl"
            return 0
        fi
    fi

    # Return any .eddx from installation
    tmpl=$(find /opt -name "*.eddx" 2>/dev/null | head -1)
    echo "$tmpl"
}
