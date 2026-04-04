#!/bin/bash
# Shared utilities for Eramba GRC tasks

ERAMBA_URL="http://localhost:8080"

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root "$path" 2>/dev/null || true
}

# Query the Eramba database directly
eramba_db_query() {
    local query="$1"
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "$query" 2>/dev/null
}

# Ensure Firefox is running and on the Eramba login page or dashboard
ensure_firefox_eramba() {
    local target_url="${1:-${ERAMBA_URL}}"
    local ff_running=false

    # Check if Firefox is running
    if pgrep -f "firefox" > /dev/null 2>&1; then
        ff_running=true
    fi

    if [ "$ff_running" = "false" ]; then
        echo "  Starting Firefox..."
        su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance ${target_url} > /tmp/firefox_task.log 2>&1 &"
        sleep 8
    fi

    # Maximize the window
    sleep 2
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

# Navigate Firefox to a URL
navigate_firefox_to() {
    local url="$1"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key --clearmodifiers ctrl+l
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool type --clearmodifiers "$url"
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return
    sleep 3
}

# Count rows in an Eramba table
count_table_rows() {
    local table="$1"
    eramba_db_query "SELECT COUNT(*) FROM ${table};" 2>/dev/null || echo "0"
}

echo "task_utils.sh loaded"
