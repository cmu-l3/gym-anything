#!/bin/bash
# Shared utilities for LibreHealth EHR task setup scripts

# ---- Window helpers ----

# Wait for a window with the given title pattern to appear
# Args: $1 - window title pattern (grep -qi pattern)
#       $2 - timeout in seconds (default: 30)
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-30}"
    local elapsed=0
    echo "Waiting for window matching '$pattern'..."
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            echo "Window found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Timeout: window not found after ${timeout}s"
    return 1
}

# Get the Firefox window ID
get_firefox_wid() {
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'
}

# Focus and maximize a window by ID
focus_and_maximize() {
    local wid="$1"
    if [ -n "$wid" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$wid" 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
}

# ---- Screenshot ----

take_screenshot() {
    local output="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root "$output" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot "$output" 2>/dev/null || \
    echo "Warning: screenshot failed"
    [ -f "$output" ] && echo "Screenshot saved: $output"
}

# ---- LibreHealth EHR DB queries ----

# Execute SQL against LibreHealth EHR database
librehealth_query() {
    # Works as root (hook context) or as ga with sudo
    if docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -N -e "$1" 2>/dev/null; then
        return 0
    fi
    sudo docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -N -e "$1" 2>/dev/null
}

# Get total patient count
get_patient_count() {
    librehealth_query "SELECT COUNT(*) FROM patient_data"
}

# Check if a patient exists by first and last name
# Returns 0 (found) or 1 (not found)
patient_exists() {
    local fname="$1"
    local lname="$2"
    local count
    count=$(librehealth_query "SELECT COUNT(*) FROM patient_data WHERE LOWER(fname)=LOWER('${fname}') AND LOWER(lname)=LOWER('${lname}')")
    [ "${count:-0}" -gt 0 ]
}

# ---- Firefox management ----

# Kill any running Firefox and start fresh at the given URL
restart_firefox() {
    local url="${1:-http://localhost:8000/interface/login/login.php?site=default}"
    # Kill existing Firefox and clean up lock files
    pkill -f firefox 2>/dev/null || true
    sleep 2
    find /home/ga/snap/firefox -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/.mozilla -name ".parentlock" -delete 2>/dev/null || true
    # Launch Firefox with correct XAUTHORITY for snap Firefox
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority firefox '$url' > /tmp/firefox_task.log 2>&1 &"
    sleep 6
    WID=$(get_firefox_wid)
    focus_and_maximize "$WID"
    # Dismiss any stray Firefox dialog
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
    sleep 0.5
}

# Wait for LibreHealth EHR to be accessible
wait_for_librehealth() {
    local timeout="${1:-120}"
    local elapsed=0
    local url="http://localhost:8000/interface/login/login.php?site=default"
    echo "Checking LibreHealth EHR accessibility..."
    while [ $elapsed -lt $timeout ]; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
        if [ "$CODE" = "200" ] || [ "$CODE" = "302" ]; then
            echo "LibreHealth EHR accessible (HTTP $CODE)"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "WARNING: LibreHealth EHR not accessible after ${timeout}s"
    return 1
}

# Export utility functions
export -f wait_for_window
export -f get_firefox_wid
export -f focus_and_maximize
export -f take_screenshot
export -f librehealth_query
export -f get_patient_count
export -f patient_exists
export -f restart_firefox
export -f wait_for_librehealth
