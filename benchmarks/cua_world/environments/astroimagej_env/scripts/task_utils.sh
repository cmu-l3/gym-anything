#!/bin/bash
# Shared utilities for AstroImageJ tasks

# Get AstroImageJ window ID
get_aij_window_id() {
    wmctrl -l 2>/dev/null | grep -i "AstroImageJ\|ImageJ\|aij" | head -1 | awk '{print $1}'
}

# Check if AstroImageJ is running
is_aij_running() {
    pgrep -f "astroimagej\|aij\|AstroImageJ" > /dev/null 2>&1
}

# Focus on AstroImageJ window
focus_aij_window() {
    local wid=$(get_aij_window_id)
    if [ -n "$wid" ]; then
        wmctrl -i -a "$wid" 2>/dev/null
        return 0
    fi
    return 1
}

# Safe xdotool command (runs as user with correct display)
safe_xdotool() {
    local user=$1
    local display=$2
    shift 2
    DISPLAY=$display sudo -u $user xdotool "$@" 2>/dev/null || true
}

# Focus any window by ID
focus_window() {
    local wid=$1
    if [ -n "$wid" ]; then
        wmctrl -i -a "$wid" 2>/dev/null
    fi
}

# Take screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Wait for window to appear (with timeout)
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-60}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            echo "Window found: $pattern"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "Timeout waiting for window: $pattern"
    return 1
}

# Launch AstroImageJ and wait for it to start
launch_astroimagej() {
    local timeout="${1:-120}"

    echo "Launching AstroImageJ..."

    # Check if already running
    if is_aij_running; then
        echo "AstroImageJ is already running"
        focus_aij_window
        return 0
    fi

    # Launch using the launch script
    su - ga -c "DISPLAY=:1 /home/ga/launch_astroimagej.sh" &

    # Give it time to start
    sleep 10

    # Wait for window
    wait_for_window "ImageJ\|AstroImageJ\|AIJ" "$timeout"

    # Additional wait for GUI to fully load
    sleep 5

    focus_aij_window

    # Check if actually running
    if is_aij_running; then
        echo "AstroImageJ launched successfully"
        return 0
    else
        echo "Warning: AstroImageJ may not have started properly"
        echo "Checking log..."
        cat /tmp/astroimagej_ga.log 2>/dev/null | tail -20
        return 1
    fi
}

# Open FITS file in AstroImageJ
open_fits_file() {
    local filepath="$1"

    if [ ! -f "$filepath" ]; then
        echo "Error: File not found: $filepath"
        return 1
    fi

    # Focus AstroImageJ
    focus_aij_window
    sleep 1

    # Use keyboard shortcut Ctrl+O to open file dialog
    safe_xdotool ga :1 key ctrl+o
    sleep 2

    # Type the filepath
    safe_xdotool ga :1 type "$filepath"
    sleep 1

    # Press Enter to open
    safe_xdotool ga :1 key Return
    sleep 3
}

# Close AstroImageJ
close_astroimagej() {
    if is_aij_running; then
        local wid=$(get_aij_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid"
            sleep 0.5
        fi
        # Try keyboard shortcut first
        safe_xdotool ga :1 key ctrl+q
        sleep 2

        # If still running, force kill
        if is_aij_running; then
            pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
        fi
    fi
}

# Get list of currently open FITS files (from AstroImageJ log)
get_open_files() {
    grep -oP "Opening: \K.*" /tmp/astroimagej_ga.log 2>/dev/null || true
}

# Check if a measurement file exists
check_measurement_file() {
    local pattern="$1"
    ls /home/ga/AstroImages/measurements/*${pattern}* 2>/dev/null | head -1
}

# Export verification helper
export_json_result() {
    local output_file="$1"
    shift

    # Create temp file first
    local temp_json=$(mktemp /tmp/result.XXXXXX.json)

    # Write JSON (caller passes content via stdin or args)
    cat > "$temp_json"

    # Copy to final location with permission handling
    rm -f "$output_file" 2>/dev/null || sudo rm -f "$output_file" 2>/dev/null || true
    cp "$temp_json" "$output_file" 2>/dev/null || sudo cp "$temp_json" "$output_file"
    chmod 666 "$output_file" 2>/dev/null || sudo chmod 666 "$output_file" 2>/dev/null || true
    rm -f "$temp_json"

    echo "Result saved to $output_file"
}
