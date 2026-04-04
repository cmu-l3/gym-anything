#!/bin/bash
# Shared utilities for 3D Slicer tasks

# Check if Slicer is running
is_slicer_running() {
    pgrep -f "Slicer" > /dev/null 2>&1
}

# Get Slicer window ID
get_slicer_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer\|3D Slicer" | head -1 | awk '{print $1}'
}

# Focus a window by ID
focus_window() {
    local wid=$1
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null || true
        sleep 0.5
    fi
}

# Safe xdotool wrapper - runs as specific user with specific display
safe_xdotool() {
    local user=$1
    local display=$2
    shift 2
    sudo -u $user DISPLAY=$display xdotool "$@" 2>/dev/null || true
}

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    local user="${2:-ga}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    sudo -u $user DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# Wait for Slicer to start AND fully load (past splash screen)
wait_for_slicer() {
    local timeout=${1:-60}
    local elapsed=0
    echo "Waiting for 3D Slicer to start..."

    # Phase 1: Wait for window to appear
    while [ $elapsed -lt $timeout ]; do
        if is_slicer_running; then
            local wid=$(get_slicer_window_id)
            if [ -n "$wid" ]; then
                echo "3D Slicer window detected (window: $wid)"
                break
            fi
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    if [ $elapsed -ge $timeout ]; then
        echo "Timeout waiting for 3D Slicer window"
        return 1
    fi

    # Phase 2: Wait for Slicer to finish loading modules
    # Slicer's window title changes when fully loaded (contains module name)
    # Also wait for CPU to settle as a heuristic
    echo "Waiting for 3D Slicer to finish loading modules..."
    local load_wait=0
    local max_load_wait=60

    while [ $load_wait -lt $max_load_wait ]; do
        # Check if window title contains "Welcome" or other module name (indicates fully loaded)
        local title=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
        if echo "$title" | grep -qi "Welcome\|Slicer [0-9]"; then
            echo "3D Slicer fully loaded (title: $title)"
            sleep 2  # Small buffer after load
            return 0
        fi

        # Check for main application window (not splash) by checking window dimensions
        local wid=$(get_slicer_window_id)
        if [ -n "$wid" ]; then
            # Get window geometry - main window is typically larger than splash
            local geom=$(DISPLAY=:1 xdotool getwindowgeometry "$wid" 2>/dev/null || echo "")
            if echo "$geom" | grep -qE "Geometry: [0-9]{3,}x[0-9]{3,}"; then
                # Window is reasonably large, likely main window
                if [ $load_wait -gt 15 ]; then
                    echo "3D Slicer appears loaded (large window detected after ${load_wait}s)"
                    sleep 2
                    return 0
                fi
            fi
        fi

        sleep 3
        load_wait=$((load_wait + 3))
    done

    # If we get here, just proceed - Slicer should be functional even if not fully initialized
    echo "3D Slicer load wait complete (waited ${load_wait}s)"
    return 0
}

# Launch Slicer with a file
launch_slicer_with_file() {
    local file="$1"
    local user="${2:-ga}"

    echo "Launching 3D Slicer with: $file"

    # Kill any existing Slicer instances
    pkill -f "Slicer" 2>/dev/null || true
    sleep 1

    # Launch Slicer
    if [ -n "$file" ] && [ -f "$file" ]; then
        sudo -u $user DISPLAY=:1 /opt/Slicer/Slicer "$file" > /tmp/slicer_launch.log 2>&1 &
    else
        sudo -u $user DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &
    fi

    # Wait for it to start
    wait_for_slicer 90
}

# Close Slicer gracefully
close_slicer() {
    if is_slicer_running; then
        local wid=$(get_slicer_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid"
            # Send Ctrl+Q to close
            safe_xdotool ga :1 key ctrl+q
            sleep 2
        fi
        # Force kill if still running
        if is_slicer_running; then
            pkill -f "Slicer" 2>/dev/null || true
        fi
    fi
}

# Get Slicer screenshot directory
get_slicer_screenshot_dir() {
    echo "/home/ga/Documents/SlicerData/Screenshots"
}

# Get sample data directory
get_sample_data_dir() {
    echo "/home/ga/Documents/SlicerData/SampleData"
}

# Check if a file was recently modified (within last N seconds)
file_modified_recently() {
    local file="$1"
    local seconds="${2:-300}"  # default 5 minutes

    if [ ! -f "$file" ]; then
        return 1
    fi

    local now=$(date +%s)
    local file_time=$(stat -c %Y "$file" 2>/dev/null || echo 0)
    local diff=$((now - file_time))

    [ $diff -lt $seconds ]
}

# List recent screenshots
list_recent_screenshots() {
    local dir=$(get_slicer_screenshot_dir)
    ls -t "$dir"/*.png 2>/dev/null | head -5
}

# Export verification result to JSON
export_result_json() {
    local output_file="$1"
    shift
    # Remaining args are key=value pairs

    # Create JSON in temp file first
    local temp_json=$(mktemp /tmp/result.XXXXXX.json)

    echo "{" > "$temp_json"
    local first=true
    while [ $# -gt 0 ]; do
        local key="${1%%=*}"
        local value="${1#*=}"
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$temp_json"
        fi
        # Handle boolean and numeric values
        if [[ "$value" =~ ^(true|false|[0-9]+)$ ]]; then
            echo "  \"$key\": $value" >> "$temp_json"
        else
            # Escape special characters in string value
            value=$(echo "$value" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
            echo "  \"$key\": \"$value\"" >> "$temp_json"
        fi
        shift
    done
    echo "" >> "$temp_json"
    echo "}" >> "$temp_json"

    # Move to final location with permission handling
    rm -f "$output_file" 2>/dev/null || sudo rm -f "$output_file" 2>/dev/null || true
    cp "$temp_json" "$output_file" 2>/dev/null || sudo cp "$temp_json" "$output_file"
    chmod 666 "$output_file" 2>/dev/null || sudo chmod 666 "$output_file" 2>/dev/null || true
    rm -f "$temp_json"

    echo "Result saved to $output_file"
    cat "$output_file"
}
