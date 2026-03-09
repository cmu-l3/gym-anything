#!/bin/bash
# Shared utilities for GeoGebra tasks

# Kill any existing GeoGebra processes for a user
kill_geogebra() {
    local username=${1:-ga}
    echo "Killing existing GeoGebra processes for user $username..."
    pkill -u "$username" -f "geogebra" 2>/dev/null || true
    pkill -u "$username" -f "GeoGebra" 2>/dev/null || true
    sleep 1
}

# Launch GeoGebra for a user
launch_geogebra() {
    local username=${1:-ga}
    local file=${2:-}
    local display=${3:-:1}

    echo "Launching GeoGebra for user $username..."

    if [ -x "/usr/bin/geogebra-classic" ]; then
        if [ -n "$file" ]; then
            su - $username -c "DISPLAY=$display geogebra-classic '$file' > /tmp/geogebra_$username.log 2>&1 &"
        else
            su - $username -c "DISPLAY=$display geogebra-classic > /tmp/geogebra_$username.log 2>&1 &"
        fi
    elif [ -x "/usr/bin/geogebra" ]; then
        if [ -n "$file" ]; then
            su - $username -c "DISPLAY=$display geogebra '$file' > /tmp/geogebra_$username.log 2>&1 &"
        else
            su - $username -c "DISPLAY=$display geogebra > /tmp/geogebra_$username.log 2>&1 &"
        fi
    elif command -v flatpak &> /dev/null && flatpak list | grep -q geogebra; then
        if [ -n "$file" ]; then
            su - $username -c "DISPLAY=$display flatpak run org.geogebra.GeoGebra '$file' > /tmp/geogebra_$username.log 2>&1 &"
        else
            su - $username -c "DISPLAY=$display flatpak run org.geogebra.GeoGebra > /tmp/geogebra_$username.log 2>&1 &"
        fi
    else
        echo "ERROR: GeoGebra not found!"
        return 1
    fi
}

# Check if GeoGebra is running
is_geogebra_running() {
    pgrep -f "geogebra" > /dev/null 2>&1 || pgrep -f "GeoGebra" > /dev/null 2>&1
    return $?
}

# Wait for a process to start
wait_for_process() {
    local process_name=$1
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for $process_name to start (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "$process_name" > /dev/null 2>&1; then
            echo "$process_name is running"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "Timeout waiting for $process_name"
    return 1
}

# Wait for a window with specific title
wait_for_window() {
    local title=$1
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for window '$title' (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$title"; then
            echo "Window '$title' found"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "Timeout waiting for window '$title'"
    return 1
}

# Get GeoGebra window ID
get_geogebra_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "geogebra" | head -1 | awk '{print $1}'
}

# Focus a window by ID
focus_window() {
    local wid=$1
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null
        sleep 0.5
    fi
}

# Focus GeoGebra window
focus_geogebra() {
    local wid=$(get_geogebra_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
        return 0
    fi
    return 1
}

# Maximize GeoGebra window
maximize_geogebra() {
    local wid=$(get_geogebra_window_id)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null
        sleep 0.5
        return 0
    fi
    return 1
}

# Safe xdotool wrapper
safe_xdotool() {
    local username=$1
    local display=$2
    shift 2
    su - $username -c "DISPLAY=$display xdotool $*" 2>/dev/null || true
}

# Take a screenshot
take_screenshot() {
    local output_path=${1:-/tmp/screenshot.png}
    DISPLAY=:1 scrot "$output_path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$output_path" 2>/dev/null || true
}

# Close GeoGebra gracefully
close_geogebra() {
    local username=${1:-ga}
    # Try Ctrl+Q first
    safe_xdotool $username :1 key ctrl+q
    sleep 2
    # If still running, kill it
    if is_geogebra_running; then
        kill_geogebra $username
    fi
}

# Export GeoGebra file list
list_geogebra_files() {
    local dir=${1:-/home/ga/Documents/GeoGebra}
    find "$dir" -name "*.ggb" -o -name "*.ggt" -o -name "*.png" -o -name "*.svg" 2>/dev/null
}

# Randomize GeoGebra viewport to prevent pre-computed coordinate attacks
# This function applies a random zoom and pan to the graphics view
randomize_geogebra_viewport() {
    local username=${1:-ga}
    local display=${2:-:1}

    # Generate random pan offsets (small range to keep view useful)
    # Range: -50 to +50 pixels from center
    local pan_x=$(( (RANDOM % 101) - 50 ))
    local pan_y=$(( (RANDOM % 101) - 50 ))

    # Generate random zoom factor (0.9 to 1.1)
    # Using scroll wheel: positive = zoom in, negative = zoom out
    local zoom_steps=$(( (RANDOM % 3) - 1 ))  # -1, 0, or 1

    echo "Randomizing viewport: pan($pan_x, $pan_y), zoom_steps($zoom_steps)"

    # First, ensure GeoGebra window is focused
    focus_geogebra
    sleep 0.3

    # Get window dimensions to find graphics view center
    # Assuming graphics view is roughly in the center-right area
    local center_x=1000
    local center_y=500

    # Move to graphics view and apply zoom using scroll wheel
    if [ $zoom_steps -ne 0 ]; then
        su - $username -c "DISPLAY=$display xdotool mousemove $center_x $center_y" 2>/dev/null || true
        sleep 0.1
        if [ $zoom_steps -gt 0 ]; then
            su - $username -c "DISPLAY=$display xdotool click 4" 2>/dev/null || true  # scroll up = zoom in
        else
            su - $username -c "DISPLAY=$display xdotool click 5" 2>/dev/null || true  # scroll down = zoom out
        fi
        sleep 0.2
    fi

    # Apply pan by dragging with right mouse button (or middle button in GeoGebra)
    # GeoGebra uses right-drag to pan
    if [ $pan_x -ne 0 ] || [ $pan_y -ne 0 ]; then
        local start_x=$center_x
        local start_y=$center_y
        local end_x=$((center_x + pan_x))
        local end_y=$((center_y + pan_y))

        # Right-click drag for pan
        su - $username -c "DISPLAY=$display xdotool mousemove $start_x $start_y mousedown 3 mousemove $end_x $end_y mouseup 3" 2>/dev/null || true
        sleep 0.3
    fi

    # Record the randomization for debugging/logging
    echo "VIEWPORT_PAN_X=$pan_x" > /tmp/viewport_randomization
    echo "VIEWPORT_PAN_Y=$pan_y" >> /tmp/viewport_randomization
    echo "VIEWPORT_ZOOM_STEPS=$zoom_steps" >> /tmp/viewport_randomization

    echo "Viewport randomization complete"
}
