#!/bin/bash
# Shared utilities for gvSIG Desktop task setup and export scripts

# Get the gvSIG launcher path
get_gvsig_launcher() {
    # First try the path saved by setup_gvsig.sh / pre_task
    if [ -f /tmp/gvsig_launcher_path ]; then
        local p; p=$(cat /tmp/gvsig_launcher_path)
        if [ -x "$p" ]; then echo "$p"; return; fi
    fi
    # Try the path saved by install_gvsig.sh
    if [ -f /etc/gvsig_launcher_path ]; then
        local p; p=$(cat /etc/gvsig_launcher_path)
        if [ -x "$p" ]; then echo "$p"; return; fi
    fi
    # Find in the deb install location
    find /usr/local/lib/gvsig-desktop -name "gvSIG.sh" 2>/dev/null | head -1
}

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# Wait for a window with specified title pattern to appear
# Args: $1 - window title pattern (grep -i pattern)
#       $2 - timeout in seconds (default: 60)
# Returns: 0 if found, 1 if timeout
wait_for_window() {
    local window_pattern="$1"
    local timeout=${2:-60}
    local elapsed=0

    echo "Waiting for window matching '$window_pattern'..."
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then
            echo "Window found after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "Timeout: Window '$window_pattern' not found after ${timeout}s"
    return 1
}

# Wait for gvSIG process to start
# Args: $1 - timeout in seconds (default: 120)
# Returns: 0 if started, 1 if timeout
wait_for_gvsig_process() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for gvSIG process..."
    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "gvSIG" > /dev/null 2>&1; then
            echo "gvSIG process found after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "Timeout: gvSIG process not found after ${timeout}s"
    return 1
}

# Kill all gvSIG instances
kill_gvsig() {
    echo "Killing gvSIG instances..."
    pkill -f "gvSIG" 2>/dev/null || true
    sleep 2
    pkill -9 -f "gvSIG" 2>/dev/null || true
    sleep 2
}

# Launch gvSIG as the ga user and wait for it to appear
# Args: $1 - optional project file to open
# Returns: 0 if window appears, 1 if timeout
launch_gvsig() {
    local project_file="$1"
    local launcher
    launcher=$(get_gvsig_launcher)

    if [ -z "$launcher" ]; then
        echo "ERROR: gvSIG launcher not found!"
        return 1
    fi

    kill_gvsig

    # Force Java 8 — gvSIG 2.4.0 uses commons-lang3 that cannot parse Java 9+ version strings
    local java8_home=""
    if [ -d /usr/lib/jvm/java-8-openjdk-amd64 ]; then
        java8_home="/usr/lib/jvm/java-8-openjdk-amd64"
    elif [ -d /usr/lib/jvm/java-1.8.0-openjdk-amd64 ]; then
        java8_home="/usr/lib/jvm/java-1.8.0-openjdk-amd64"
    fi

    echo "Launching gvSIG: $launcher $project_file (JAVA_HOME=$java8_home)"
    if [ -n "$project_file" ] && [ -f "$project_file" ]; then
        su - ga -c "LC_NUMERIC=C JAVA_HOME='$java8_home' DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority '$launcher' '$project_file' > /tmp/gvsig_task.log 2>&1 &"
    else
        su - ga -c "LC_NUMERIC=C JAVA_HOME='$java8_home' DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority '$launcher' > /tmp/gvsig_task.log 2>&1 &"
    fi

    # Wait for gvSIG process to appear
    wait_for_gvsig_process 120 || return 1

    # Wait for window
    echo "Waiting for gvSIG window..."
    local elapsed=0
    while [ $elapsed -lt 90 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "gvsig\|Project Manager\|andami"; then
            echo "gvSIG window appeared after ${elapsed}s"
            sleep 5  # Extra time for full initialization
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done

    echo "WARNING: gvSIG window title not detected, but process is running"
    sleep 5
    return 0
}

# Verify the Natural Earth countries shapefile exists
check_countries_shapefile() {
    local shp_file
    shp_file=$(ls /home/ga/gvsig_data/countries/*.shp 2>/dev/null | head -1)
    if [ -z "$shp_file" ]; then
        echo "ERROR: Countries shapefile not found in /home/ga/gvsig_data/countries/"
        return 1
    fi
    echo "Countries shapefile: $shp_file"
    return 0
}

# Export functions for use in other scripts
export -f get_gvsig_launcher
export -f take_screenshot
export -f wait_for_window
export -f wait_for_gvsig_process
export -f kill_gvsig
export -f launch_gvsig
export -f check_countries_shapefile
