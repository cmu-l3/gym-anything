#!/bin/bash
# Shared utilities for JFrog Artifactory tasks
# Source this file at the start of each setup_task.sh:
#   source /workspace/scripts/task_utils.sh

ARTIFACTORY_URL="http://localhost:8082"
ADMIN_USER="admin"
ADMIN_PASS="password"

# ============================================================
# Artifactory REST API
# ============================================================
art_api() {
    local method="$1"
    local path="$2"
    local data="${3:-}"
    if [ -n "$data" ]; then
        curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
            -X "$method" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "${ARTIFACTORY_URL}/artifactory${path}" 2>/dev/null
    else
        curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
            -X "$method" \
            "${ARTIFACTORY_URL}/artifactory${path}" 2>/dev/null
    fi
}

# Check if a repository exists
# Usage: repo_exists "my-repo-key"
# NOTE: In Artifactory OSS 7.x, the individual repo detail endpoint returns 400 (Pro-only).
# This function uses the list endpoint and parses for the repo key.
repo_exists() {
    local repo_key="$1"
    curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "${ARTIFACTORY_URL}/artifactory/api/repositories" 2>/dev/null | \
        python3 -c "
import sys, json
try:
    repos = json.load(sys.stdin)
    keys = [r.get('key', '') for r in repos]
    sys.exit(0 if '$repo_key' in keys else 1)
except:
    sys.exit(1)
" 2>/dev/null
}

# Get repository count
get_repo_count() {
    art_api GET "/api/repositories" | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null || echo "0"
}

# Get repository info as JSON
get_repo_info() {
    local repo_key="$1"
    art_api GET "/api/repositories/${repo_key}"
}

# Check if a user exists
# Usage: user_exists "username" ["password"]
# NOTE: In Artifactory OSS 7.x, GET /api/security/users/{name} returns 400 (Pro-only).
# This function tries the endpoint first; if 400, falls back to credential-based auth check.
user_exists() {
    local username="$1"
    local user_pass="${2:-}"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "${ARTIFACTORY_URL}/artifactory/api/security/users/${username}" 2>/dev/null)
    if [ "$status" = "200" ]; then
        return 0
    elif [ "$status" = "404" ]; then
        return 1
    fi
    # HTTP 400 = Pro-only restriction; try credential auth if password provided
    if [ -n "$user_pass" ]; then
        local auth_status
        auth_status=$(curl -s -o /dev/null -w "%{http_code}" \
            -u "${username}:${user_pass}" \
            "${ARTIFACTORY_URL}/artifactory/api/system/ping" 2>/dev/null)
        [ "$auth_status" = "200" ]
    else
        return 1  # Cannot determine existence without password in OSS
    fi
}

# Get user count
get_user_count() {
    art_api GET "/api/security/users" | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null || echo "0"
}

# Check if a group exists
group_exists() {
    local groupname="$1"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "${ARTIFACTORY_URL}/artifactory/api/security/groups/${groupname}" 2>/dev/null)
    [ "$status" = "200" ]
}

# Check if a permission target exists
permission_exists() {
    local perm_name="$1"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        "${ARTIFACTORY_URL}/artifactory/api/security/permissions/${perm_name}" 2>/dev/null)
    [ "$status" = "200" ]
}

# Check if Artifactory is accessible
wait_for_artifactory() {
    local timeout=${1:-120}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            -u "${ADMIN_USER}:${ADMIN_PASS}" \
            "${ARTIFACTORY_URL}/artifactory/api/system/ping" 2>/dev/null)
        if [ "$STATUS" = "200" ]; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

# Delete a repository if it exists (for clean task setup)
delete_repo_if_exists() {
    local repo_key="$1"
    if repo_exists "$repo_key"; then
        art_api DELETE "/api/repositories/${repo_key}" > /dev/null 2>&1 || true
        echo "Deleted existing repository: $repo_key"
    fi
}

# Delete a user — attempts DELETE directly without pre-checking existence.
# In Artifactory OSS 7.x, GET /api/security/users/{name} returns 400 (Pro-only),
# so we skip the existence check and just attempt DELETE (idempotent, fails silently
# if user doesn't exist or if the endpoint is restricted).
delete_user_if_exists() {
    local username="$1"
    art_api DELETE "/api/security/users/${username}" > /dev/null 2>&1 || true
    echo "Attempted cleanup of user: $username"
}

# Delete a group — attempts DELETE directly (same reason as delete_user_if_exists).
delete_group_if_exists() {
    local groupname="$1"
    art_api DELETE "/api/security/groups/${groupname}" > /dev/null 2>&1 || true
    echo "Attempted cleanup of group: $groupname"
}

# Delete a permission target — attempts DELETE directly.
delete_permission_if_exists() {
    local perm_name="$1"
    art_api DELETE "/api/security/permissions/${perm_name}" > /dev/null 2>&1 || true
    echo "Attempted cleanup of permission target: $perm_name"
}

# Take screenshot
# Priority: gnome-screenshot (captures Wayland windows) > scrot > xwd+convert
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    local xdg_runtime="/run/user/1000"
    local xauth="/run/user/1000/gdm/Xauthority"
    [ -f "$xauth" ] || xauth="/home/ga/.Xauthority"

    # Method 1: gnome-screenshot — captures Wayland-native windows (snap Firefox)
    su - ga -c "
        export DISPLAY=:1
        export XAUTHORITY='${xauth}'
        export XDG_RUNTIME_DIR='${xdg_runtime}'
        gnome-screenshot -f '${path}' 2>/dev/null
    " 2>/dev/null
    if [ -f "$path" ] && [ -s "$path" ]; then
        echo "Screenshot saved: $path ($(du -h "$path" | cut -f1)) [gnome-screenshot]"
        return
    fi

    # Method 2: scrot (X11 only)
    DISPLAY=:1 scrot "$path" 2>/dev/null
    if [ -f "$path" ] && [ -s "$path" ]; then
        echo "Screenshot saved: $path ($(du -h "$path" | cut -f1)) [scrot]"
        return
    fi

    # Method 3: xwd + convert (X11 only fallback)
    DISPLAY=:1 xwd -root -silent 2>/dev/null | convert - "$path" 2>/dev/null || true
    if [ -f "$path" ] && [ -s "$path" ]; then
        echo "Screenshot saved: $path ($(du -h "$path" | cut -f1)) [xwd]"
    else
        echo "WARNING: Screenshot capture failed for $path"
    fi
}

# Wait for Firefox window
wait_for_firefox() {
    local timeout=${1:-30}
    for i in $(seq 1 $timeout); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Get Firefox window ID
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}'
}

# Focus and maximize Firefox
focus_firefox() {
    local wid
    wid=$(get_firefox_window_id)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        sleep 0.5
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 0.5
    fi
}

# Navigate Firefox to a URL and wait for page to load
navigate_to() {
    local url="$1"
    focus_firefox
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "$url" 2>/dev/null
    sleep 0.3
    DISPLAY=:1 xdotool key Return 2>/dev/null
    # Wait for page load: Artifactory SPA pages can take 5-10s to render
    sleep 12
}

# Determine the correct Firefox profile path (snap vs deb)
# setup_artifactory.sh writes the detected path to /tmp/firefox_profile_path
get_firefox_profile() {
    if [ -f /tmp/firefox_profile_path ]; then
        # shellcheck disable=SC1091
        source /tmp/firefox_profile_path 2>/dev/null
        if [ -n "${FIREFOX_PROFILE:-}" ]; then
            echo "$FIREFOX_PROFILE"
            return
        fi
    fi
    # Fallback: detect snap vs deb at runtime
    if [ -d "/snap/firefox" ] || [ -d "/var/lib/snapd/snap/firefox" ]; then
        echo "/home/ga/snap/firefox/common/.mozilla/firefox/artifactory.profile"
    else
        echo "/home/ga/.mozilla/firefox/artifactory.profile"
    fi
}

# Ensure Firefox is running and showing Artifactory.
# Always checks for a visible window (not just a process) and relaunches if needed.
ensure_firefox_running() {
    local url="${1:-http://localhost:8082}"

    # Check if Firefox window is already visible
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|artifactory"; then
        echo "Firefox window already visible"
        focus_firefox
        sleep 1
        return 0
    fi

    echo "No Firefox window found, (re)launching..."

    # Kill ALL Firefox processes aggressively (snap uses different process names)
    pkill -9 -f firefox 2>/dev/null || true
    pkill -9 -f 'snap.*firefox' 2>/dev/null || true
    pkill -9 -f 'Web Content' 2>/dev/null || true
    killall -9 firefox firefox-bin 2>/dev/null || true
    sleep 5

    # Clean lock files from all possible locations
    find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true
    find /home/ga/snap/firefox/ -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/snap/firefox/ -name "lock" -delete 2>/dev/null || true

    # Ensure snap Firefox can create its revision directory
    chown -R ga:ga /home/ga/snap 2>/dev/null || true

    # Use simple launch command (matching proven rancher_env pattern)
    su - ga -c "DISPLAY=:1 setsid firefox '${url}' > /tmp/firefox_task.log 2>&1 &"

    # Wait for snap Firefox to fully start (snap adds overhead)
    sleep 15

    # Wait up to 60s for Firefox window to appear
    wait_for_firefox 60 || true
    focus_firefox
    # Give the page additional time to render after focus
    sleep 3
}
