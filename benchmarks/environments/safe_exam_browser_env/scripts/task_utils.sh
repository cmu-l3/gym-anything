#!/bin/bash
# Shared utilities for SEB Server tasks

SEB_SERVER_URL="http://localhost:8080"
SEB_ADMIN_USER="super-admin"
SEB_ADMIN_PASS="admin"

# ============================================================
# Screenshot utilities
# ============================================================
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || true
}

# ============================================================
# Wait for SEB Server to be accessible
# ============================================================
wait_for_seb_server() {
    local timeout="${1:-120}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${SEB_SERVER_URL}/gui" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "401" ]; then
            echo "SEB Server is accessible (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "WARNING: SEB Server not accessible after ${timeout}s"
    return 1
}

# ============================================================
# MariaDB query via Docker
# ============================================================
seb_db_query() {
    local query="$1"
    docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "$query" 2>/dev/null
}

seb_db_query_json() {
    local query="$1"
    docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer --batch -e "$query" 2>/dev/null
}

# ============================================================
# Firefox management
# ============================================================
get_firefox_profile_dir() {
    if snap list firefox 2>/dev/null | grep -q firefox; then
        echo "/home/ga/snap/firefox/common/.mozilla/firefox/seb.profile"
    else
        echo "/home/ga/.mozilla/firefox/seb.profile"
    fi
}

launch_firefox() {
    local url="${1:-$SEB_SERVER_URL}"
    local profile_dir
    profile_dir=$(get_firefox_profile_dir)

    # Kill existing Firefox
    pkill -9 -f firefox 2>/dev/null || true
    sleep 2

    # Remove stale locks
    local profile_base
    profile_base=$(dirname "$profile_dir")
    find "$profile_base" -name "lock" -o -name ".parentlock" 2>/dev/null | xargs rm -f 2>/dev/null || true

    # Remove stale session data
    find "$profile_dir" -name "sessionstore*" -delete 2>/dev/null || true
    rm -rf "${profile_dir}/sessionstore-backups" 2>/dev/null || true

    # Launch Firefox
    su - ga -c "DISPLAY=:1 setsid firefox --new-instance -profile '${profile_dir}' '${url}' > /tmp/firefox_task.log 2>&1 &"
    sleep 8

    # Wait for Firefox window
    local timeout=30
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
            echo "Firefox window detected"
            # Maximize the window
            DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Firefox window not detected after ${timeout}s"
    return 1
}

navigate_firefox() {
    local url="$1"
    # Use Ctrl+L to focus address bar, type URL, press Enter
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+l 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+a 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers "$url" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return 2>/dev/null || true
    sleep 3
}

# ============================================================
# SEB Server login via browser
# ============================================================
login_seb_server() {
    local username="${1:-$SEB_ADMIN_USER}"
    local password="${2:-$SEB_ADMIN_PASS}"

    echo "Logging into SEB Server as $username..."

    # Navigate to login page
    navigate_firefox "${SEB_SERVER_URL}"
    sleep 5

    # The login page has username and password fields
    # Use xdotool to fill in credentials
    # Tab to username field and type
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Tab 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers "$username" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Tab 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers "$password" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return 2>/dev/null || true
    sleep 5
}

# ============================================================
# Baseline recording for anti-gaming
# ============================================================
record_baseline() {
    local task_name="$1"
    python3 /workspace/data/record_baseline.py "$task_name"
}
