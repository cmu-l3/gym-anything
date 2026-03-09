#!/bin/bash
# Shared utilities for Sweet Home 3D tasks

# Take a screenshot and save to specified path
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Kill any running Sweet Home 3D instances
kill_sweet_home_3d() {
    pkill -f "SweetHome3D" 2>/dev/null || true
    sleep 2
    pkill -9 -f "SweetHome3D" 2>/dev/null || true
    pkill -9 -f "sweethome3d" 2>/dev/null || true
    sleep 1
}

# Launch Sweet Home 3D with a specific file and wait for window
# NOTE: The SweetHome3D launcher already adds -open "$1", so pass
# the file path directly as argument — do NOT add -open yourself.
launch_sweet_home_3d() {
    local file_path="$1"
    local timeout="${2:-90}"
    local elapsed=0

    if [ -n "$file_path" ]; then
        su - ga -c "DISPLAY=:1 /opt/SweetHome3D/SweetHome3D \"$file_path\" > /tmp/sh3d_launch.log 2>&1 &"
    else
        su - ga -c "DISPLAY=:1 /opt/SweetHome3D/SweetHome3D > /tmp/sh3d_launch.log 2>&1 &"
    fi

    # Wait for the main application window to appear.
    # The window title contains the filename when a file is loaded,
    # or "Sweet Home 3D" for an empty plan. The Java class name
    # "com-eteks-sweethome3d-SweetHome3D" is also findable by class.
    # Use a broad search: look for any window with "sweethome3d" in the class name.
    while [ $elapsed -lt $timeout ]; do
        # Search by window class (most reliable for Java apps)
        WID=$(DISPLAY=:1 xdotool search --class "sweethome3d" 2>/dev/null | head -1)
        if [ -z "$WID" ]; then
            # Also search by partial name match
            WID=$(DISPLAY=:1 xdotool search --name "Sweet Home" 2>/dev/null | head -1)
        fi
        if [ -z "$WID" ]; then
            # Also try the Java class name pattern
            WID=$(DISPLAY=:1 xdotool search --name "com-eteks-sweethome3d" 2>/dev/null | head -1)
        fi
        if [ -n "$WID" ]; then
            echo "Sweet Home 3D window detected after ${elapsed}s (WID: $WID)"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "WARNING: Sweet Home 3D window not detected after ${timeout}s"
    return 1
}

# Find and return the Sweet Home 3D main window ID
find_sh3d_window() {
    local WID=""
    # Try by class name first
    WID=$(DISPLAY=:1 xdotool search --class "sweethome3d" 2>/dev/null | tail -1)
    if [ -z "$WID" ]; then
        WID=$(DISPLAY=:1 xdotool search --name "Sweet Home" 2>/dev/null | head -1)
    fi
    if [ -z "$WID" ]; then
        WID=$(DISPLAY=:1 xdotool search --name "com-eteks-sweethome3d" 2>/dev/null | head -1)
    fi
    echo "$WID"
}

# Maximize the Sweet Home 3D window
maximize_sweet_home_3d() {
    local WID=$(find_sh3d_window)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        echo "Window maximized and focused (WID: $WID)"
    else
        echo "WARNING: Could not find Sweet Home 3D window to maximize"
    fi
}

# Dismiss startup dialogs (tips, update checks, etc.)
dismiss_dialogs() {
    local rounds="${1:-5}"
    for attempt in $(seq 1 $rounds); do
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 0.5
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 0.5
    done
}

# Full task setup: kill old instance, launch with file, maximize, dismiss dialogs
setup_sweet_home_3d_task() {
    local file_path="$1"

    echo "Killing any existing Sweet Home 3D instances..."
    kill_sweet_home_3d

    echo "Launching Sweet Home 3D..."
    launch_sweet_home_3d "$file_path"

    # Extra wait for the application to fully render after window appears
    echo "Waiting for application to fully load..."
    sleep 10

    echo "Dismissing startup dialogs..."
    dismiss_dialogs 5

    echo "Maximizing window..."
    maximize_sweet_home_3d
    sleep 2

    echo "Taking initial screenshot..."
    take_screenshot /tmp/task_start_screenshot.png

    echo "Sweet Home 3D task setup complete"
}
