#!/bin/bash
# Shared utilities for OpenKM tasks

OPENKM_URL="http://localhost:8080/OpenKM"
OPENKM_API="http://localhost:8080/OpenKM/services/rest"
OPENKM_USER="okmAdmin"
OPENKM_PASS="admin"

# ── Fix X11 authentication (CRITICAL) ────────────────────────────────────────
# GDM stores Xauthority at /run/user/1000/gdm/Xauthority, not ~/.Xauthority
# Without this fix, xdotool/pyautogui mouse events cannot reach Firefox
fix_xauthority() {
    local gdm_auth="/run/user/1000/gdm/Xauthority"
    local user_auth="/home/ga/.Xauthority"
    if [ -f "$gdm_auth" ] && [ -s "$gdm_auth" ]; then
        if [ ! -s "$user_auth" ]; then
            cp "$gdm_auth" "$user_auth"
            chown ga:ga "$user_auth"
            echo "Fixed Xauthority from GDM session"
        fi
    fi
}
fix_xauthority

# ── Ensure OpenKM is running ─────────────────────────────────────────────────
ensure_openkm_running() {
    # Ensure Docker is running
    if ! systemctl is-active docker >/dev/null 2>&1; then
        echo "Starting Docker..."
        sudo systemctl start docker
        sleep 5
    fi

    # Ensure OpenKM container is running
    if ! sudo docker ps --format '{{.Names}}' | grep -q openkm-ce; then
        echo "Starting OpenKM container..."
        sudo docker start openkm-ce 2>/dev/null || {
            sudo docker run -d --name openkm-ce -p 8080:8080 --restart unless-stopped \
                -v openkm_data:/opt/openkm openkm/openkm-ce:latest
        }
    fi

    # Wait for OpenKM to respond (use login.jsp which returns 200)
    local timeout=180
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${OPENKM_URL}/login.jsp" 2>/dev/null)
        if echo "$http_code" | grep -qE "^[2-3][0-9][0-9]$"; then
            echo "OpenKM is accessible (HTTP $http_code)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "WARNING: OpenKM not responding after ${timeout}s"
    return 1
}

# ── Take screenshot ──────────────────────────────────────────────────────────
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || true
}

# ── Focus Firefox window ─────────────────────────────────────────────────────
focus_firefox() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a "Mozilla Firefox" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a "OpenKM" 2>/dev/null || true
    sleep 0.5
}

# ── Maximize Firefox window ──────────────────────────────────────────────────
maximize_firefox() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 0.5
}

# ── Navigate to URL in Firefox ────────────────────────────────────────────────
navigate_to() {
    local url="$1"
    focus_firefox
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers "$url"
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return
    sleep 5
}

# ── Log in to OpenKM via UI ──────────────────────────────────────────────────
auto_login_openkm() {
    local dest="${1:-}"

    focus_firefox
    maximize_firefox
    sleep 2

    # Navigate to login page
    navigate_to "${OPENKM_URL}/login.jsp"
    sleep 5

    # The login form auto-focuses the username field via onload
    # Type username directly (field is already focused)
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers --delay 30 "${OPENKM_USER}"
    sleep 0.3

    # Tab to password field
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Tab
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers --delay 30 "${OPENKM_PASS}"
    sleep 0.3

    # Press Enter to submit the login form
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return
    sleep 10

    # Dismiss any save-password prompt
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape
    sleep 1

    # Navigate to destination if specified
    if [ -n "$dest" ]; then
        navigate_to "$dest"
    fi
}

# ── Launch Firefox cleanly ────────────────────────────────────────────────────
launch_firefox() {
    local url="${1:-${OPENKM_URL}/login.jsp}"

    # Kill existing Firefox
    sudo pkill -9 firefox 2>/dev/null || true
    sleep 2

    # Remove lock files and session restore data
    find /home/ga -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga -name "parent.lock" -delete 2>/dev/null || true
    find /home/ga -path "*/sessionstore*" -delete 2>/dev/null || true

    # Launch Firefox
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid firefox "$url" &>/dev/null &

    # Wait for Firefox window
    for i in {1..30}; do
        if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "Firefox\|Mozilla\|OpenKM"; then
            echo "Firefox window detected"
            break
        fi
        sleep 1
    done

    focus_firefox
    maximize_firefox
    sleep 3
}

# ── OpenKM REST API helper ───────────────────────────────────────────────────
openkm_api() {
    local method="$1"
    local endpoint="$2"
    shift 2
    curl -s -u "${OPENKM_USER}:${OPENKM_PASS}" \
        -H "Accept: application/json" \
        -X "$method" \
        "$@" \
        "${OPENKM_API}/${endpoint}" 2>/dev/null
}

# ── Add keyword to a document ─────────────────────────────────────────────────
openkm_add_keyword() {
    local doc_path="$1"
    local keyword="$2"
    curl -s -o /dev/null -w "%{http_code}" \
        -u "${OPENKM_USER}:${OPENKM_PASS}" \
        -X POST \
        "${OPENKM_API}/property/addKeyword?nodeId=${doc_path}&keyword=${keyword}" 2>/dev/null
}

# ── Check if a document exists in OpenKM ──────────────────────────────────────
openkm_doc_exists() {
    local doc_path="$1"
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${OPENKM_USER}:${OPENKM_PASS}" \
        -H "Accept: application/json" \
        "${OPENKM_API}/document/getProperties?docId=${doc_path}" 2>/dev/null)
    [ "$response" = "200" ]
}

# ── List children of a folder ─────────────────────────────────────────────────
openkm_list_folder() {
    local folder_path="$1"
    curl -s -u "${OPENKM_USER}:${OPENKM_PASS}" \
        -H "Accept: application/json" \
        "${OPENKM_API}/folder/getChildren?fldId=${folder_path}" 2>/dev/null
}

# Auto-start OpenKM when sourced
ensure_openkm_running
