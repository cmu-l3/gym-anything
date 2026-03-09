#!/bin/bash
# Shared utilities for Thunderbird environment tasks

# ============================================================
# Screenshot utilities
# ============================================================
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    local user="${2:-ga}"
    su - "$user" -c "DISPLAY=:1 scrot '$path'" 2>/dev/null || \
    su - "$user" -c "DISPLAY=:1 import -window root '$path'" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# ============================================================
# Thunderbird process management
# ============================================================
THUNDERBIRD_PROFILE="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${THUNDERBIRD_PROFILE}/Mail/Local Folders"

is_thunderbird_running() {
    pgrep -f "thunderbird" > /dev/null 2>&1
}

get_thunderbird_pid() {
    pgrep -f "thunderbird" | head -1
}

start_thunderbird() {
    if ! is_thunderbird_running; then
        su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release &" 2>/dev/null
        sleep 8  # Give Thunderbird time to start and index
    fi
}

close_thunderbird() {
    if is_thunderbird_running; then
        # Try graceful close first
        su - ga -c "DISPLAY=:1 wmctrl -c 'Thunderbird'" 2>/dev/null || true
        sleep 2
        # Force kill if still running
        if is_thunderbird_running; then
            pkill -f "thunderbird" 2>/dev/null || true
            sleep 1
        fi
    fi
}

maximize_thunderbird() {
    local WID
    WID=$(su - ga -c "DISPLAY=:1 xdotool search --name 'Thunderbird' 2>/dev/null" | head -1)
    if [ -n "$WID" ]; then
        su - ga -c "DISPLAY=:1 wmctrl -i -r '$WID' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    fi
}

wait_for_thunderbird_window() {
    local timeout="${1:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if su - ga -c "DISPLAY=:1 xdotool search --name 'Thunderbird' 2>/dev/null" | head -1 | grep -q .; then
            echo "Thunderbird window found"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "Thunderbird window not found after ${timeout}s"
    return 1
}

# ============================================================
# Email folder utilities
# ============================================================
count_emails_in_mbox() {
    local mbox_file="$1"
    local count=0
    if [ -f "$mbox_file" ]; then
        count=$(grep -c "^From " "$mbox_file" 2>/dev/null || true)
        # Ensure we have a valid integer
        count=$(echo "$count" | tr -d '[:space:]')
        if ! [[ "$count" =~ ^[0-9]+$ ]]; then
            count=0
        fi
    fi
    echo "$count"
}

list_local_folders() {
    # List all mbox files (folders) in Local Folders
    ls -1 "$LOCAL_MAIL_DIR" 2>/dev/null | grep -v '\.msf$' | grep -v '\.sbd$' || echo ""
}

folder_exists() {
    local folder_name="$1"
    [ -f "${LOCAL_MAIL_DIR}/${folder_name}" ]
}

# ============================================================
# Window detection utilities
# ============================================================
get_thunderbird_windows() {
    su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "thunderbird" || echo ""
}

has_compose_window() {
    su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -iE "(write|compose|new message)" > /dev/null 2>&1
}

has_filter_dialog() {
    su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -iE "(filter|message filter)" > /dev/null 2>&1
}

# ============================================================
# prefs.js reading utilities
# ============================================================
get_thunderbird_pref() {
    local pref_name="$1"
    local prefs_file="${THUNDERBIRD_PROFILE}/prefs.js"
    if [ -f "$prefs_file" ]; then
        grep "\"${pref_name}\"" "$prefs_file" 2>/dev/null | sed 's/.*,\s*//' | sed 's/);\s*$//' | tr -d '"' || echo ""
    else
        echo ""
    fi
}
