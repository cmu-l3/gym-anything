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
    # Use -h 127.0.0.1 to force TCP connection (avoids socket issues)
    if docker exec librehealth-db mysql -h 127.0.0.1 -u libreehr -ps3cret libreehr -N -e "$1" 2>/dev/null; then
        return 0
    fi
    sudo docker exec librehealth-db mysql -h 127.0.0.1 -u libreehr -ps3cret libreehr -N -e "$1" 2>/dev/null
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

    # Re-trust desktop shortcut (may have been lost after VM restore)
    su - ga -c "dbus-launch gio set /home/ga/Desktop/LibreHealth.desktop metadata::trusted true" 2>/dev/null || true

    # Wait for LibreHealth to be accessible before launching Firefox
    echo "Waiting for LibreHealth to be accessible before Firefox launch..."
    local _w=0
    while [ $_w -lt 60 ]; do
        local _code
        _code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8000/interface/login/login.php?site=default" 2>/dev/null || echo "000")
        if [ "$_code" = "200" ] || [ "$_code" = "302" ]; then
            echo "LibreHealth reachable (HTTP $_code)"
            break
        fi
        sleep 3
        _w=$((_w + 3))
    done

    # Kill existing Firefox and clean up lock files
    pkill -f firefox 2>/dev/null || true
    sleep 3
    # Force kill if still alive
    pkill -9 -f firefox 2>/dev/null || true
    sleep 1
    find /home/ga/snap/firefox -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/.mozilla -name ".parentlock" -delete 2>/dev/null || true
    # Launch Firefox with correct XAUTHORITY
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority firefox '$url' > /tmp/firefox_task.log 2>&1 &"
    # Snap Firefox can take 10+ seconds to start on first launch
    sleep 10
    # Wait for window to appear (extended to 60s for snap Firefox)
    for i in $(seq 1 60); do
        WID=$(get_firefox_wid)
        if [ -n "$WID" ]; then
            echo "Firefox window detected after ${i}s"
            break
        fi
        sleep 1
    done
    WID=$(get_firefox_wid)
    if [ -z "$WID" ]; then
        echo "Firefox not found, retrying launch..."
        pkill -9 -f firefox 2>/dev/null || true
        sleep 2
        find /home/ga/snap/firefox -name ".parentlock" -delete 2>/dev/null || true
        find /home/ga/.mozilla -name ".parentlock" -delete 2>/dev/null || true
        su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority firefox '$url' > /tmp/firefox_task2.log 2>&1 &"
        sleep 15
        for i in $(seq 1 30); do
            WID=$(get_firefox_wid)
            if [ -n "$WID" ]; then
                echo "Firefox window detected on retry after ${i}s"
                break
            fi
            sleep 1
        done
        WID=$(get_firefox_wid)
    fi
    focus_and_maximize "$WID"
    # Dismiss any stray Firefox dialog
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
    sleep 1
}

# Wait for LibreHealth EHR to be accessible
# After cache restore (VM reboot), Docker containers may need restarting
wait_for_librehealth() {
    local timeout="${1:-120}"
    # Enforce minimum 120s timeout to handle post-cache-restore cold boots
    if [ "$timeout" -lt 120 ]; then
        timeout=120
    fi
    local elapsed=0
    local url="http://localhost:8000/interface/login/login.php?site=default"
    echo "Checking LibreHealth EHR accessibility (timeout: ${timeout}s)..."

    # Ensure Docker is running and containers are up (needed after cache restore / reboot)
    if command -v docker >/dev/null 2>&1; then
        if ! docker ps >/dev/null 2>&1; then
            echo "Docker not ready, waiting for Docker daemon..."
            for _d in $(seq 1 30); do
                if docker info >/dev/null 2>&1; then
                    echo "Docker daemon ready"
                    break
                fi
                sleep 2
            done
        fi
        # Start containers if they're not running
        if [ -f /home/ga/librehealth/docker-compose.yml ]; then
            if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "librehealth-app"; then
                echo "Starting LibreHealth containers..."
                docker compose -f /home/ga/librehealth/docker-compose.yml up -d 2>/dev/null || true
            fi
        fi
    fi

    while [ $elapsed -lt $timeout ]; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
        if [ "$CODE" = "200" ] || [ "$CODE" = "302" ]; then
            echo "LibreHealth EHR accessible (HTTP $CODE) after ${elapsed}s"
            # Relax SQL strict mode (lost on MariaDB restart after cache restore)
            # Without this, INSERTs that omit non-nullable columns fail with
            # ERROR 1364: Field 'X' doesn't have a default value
            docker exec librehealth-db mysql -h 127.0.0.1 -uroot -pm4ster_s3cret -e \
                "SET GLOBAL sql_mode='NO_ENGINE_SUBSTITUTION'" 2>/dev/null || true
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
