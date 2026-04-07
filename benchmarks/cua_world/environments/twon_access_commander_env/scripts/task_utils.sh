#!/bin/bash
# Shared utilities for 2N Access Commander tasks.
# Source this file: source /workspace/scripts/task_utils.sh

AC_URL="https://localhost:9443"
AC_USER="admin"
AC_PASS="Admin2n1!"
XAUTH="/run/user/1000/gdm/Xauthority"
COOKIE_JAR="/tmp/ac_cookies.txt"

# Firefox profile location: snap firefox uses a different base path on Ubuntu 22.04
# Always prefer the snap path since Ubuntu 22.04 uses snap Firefox by default.
# The non-snap path may also exist but AppArmor blocks snap Firefox from accessing it.
SNAP_FF_PROFILE="/home/ga/snap/firefox/common/.mozilla/firefox/accommander.profile"
SYS_FF_PROFILE="/home/ga/.mozilla/firefox/accommander.profile"
if snap list firefox > /dev/null 2>&1 || [ -d "/home/ga/snap/firefox" ]; then
    PROFILE_DIR="$SNAP_FF_PROFILE"
else
    PROFILE_DIR="$SYS_FF_PROFILE"
fi

# -------------------------------------------------------
# Screenshot helper
# -------------------------------------------------------
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=$XAUTH scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=$XAUTH import -window root "$path" 2>/dev/null || true
}

# -------------------------------------------------------
# Wait for AC inner VM to be reachable (up to 5 min)
# -------------------------------------------------------
wait_for_ac_demo() {
    local timeout=300
    local elapsed=0
    echo "Waiting for $AC_URL ..."
    while [ $elapsed -lt $timeout ]; do
        if curl -sk --max-time 5 "$AC_URL" > /dev/null 2>&1; then
            echo "AC reachable (${elapsed}s)"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    echo "WARNING: AC may not be reachable after ${timeout}s"
    return 1
}

# -------------------------------------------------------
# REST API authentication: creates session cookie file
# -------------------------------------------------------
ac_login() {
    rm -f "$COOKIE_JAR"
    local http_code
    http_code=$(curl -sk \
        -c "$COOKIE_JAR" \
        -o /tmp/ac_login_resp.json \
        -w "%{http_code}" \
        -X PUT \
        -H "Content-Type: application/json" \
        -d "{\"login\":\"${AC_USER}\",\"password\":\"${AC_PASS}\"}" \
        "${AC_URL}/api/v3/login")
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        echo "API login successful (HTTP $http_code)"
        return 0
    else
        echo "API login failed (HTTP $http_code)"
        cat /tmp/ac_login_resp.json 2>/dev/null || true
        return 1
    fi
}

# -------------------------------------------------------
# Generic API call (requires prior ac_login)
# -------------------------------------------------------
ac_api() {
    local method="$1"
    local endpoint="$2"
    local body="${3:-}"
    if [ -n "$body" ]; then
        curl -sk -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
            -X "$method" \
            -H "Content-Type: application/json" \
            -d "$body" \
            "${AC_URL}/api/v3${endpoint}"
    else
        curl -sk -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
            -X "$method" \
            "${AC_URL}/api/v3${endpoint}"
    fi
}

# -------------------------------------------------------
# Launch Firefox pointing at a specific AC page
# Uses system Firefox (not snap)
# -------------------------------------------------------
launch_firefox_to() {
    local url="$1"
    local wait_sec="${2:-6}"

    # Stop any previous systemd transient unit and kill stale Firefox
    systemctl --user --machine=ga@ stop firefox-ac.service 2>/dev/null || true
    pkill -9 -f "firefox" 2>/dev/null || true
    sleep 2

    # Remove stale lock
    rm -f "$PROFILE_DIR/.parentlock" "$PROFILE_DIR/lock" 2>/dev/null || true

    # Launch Firefox using the raw binary (bypasses snap confinement which
    # causes "Profile Missing" errors). Use nohup so Firefox survives SSH close.
    local FF_BIN
    FF_BIN=$(find /snap/firefox/current/usr/lib/firefox/firefox -maxdepth 0 2>/dev/null || \
             find /snap/firefox/*/usr/lib/firefox/firefox -maxdepth 0 2>/dev/null | head -1)
    if [ -z "$FF_BIN" ]; then
        FF_BIN="firefox"  # fallback to snap wrapper
    fi

    su - ga -c "DISPLAY=:1 XAUTHORITY=$XAUTH \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
        nohup $FF_BIN \
        --new-instance \
        -profile '$PROFILE_DIR' \
        '$url' > /dev/null 2>&1 &"

    sleep "$wait_sec"

    # Dismiss any dialogs
    DISPLAY=:1 XAUTHORITY=$XAUTH xdotool key Escape 2>/dev/null || true
    sleep 1

    # Maximize
    DISPLAY=:1 XAUTHORITY=$XAUTH wmctrl -r "Mozilla Firefox" \
        -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
}

# -------------------------------------------------------
# Clean up test data created by previous task runs
# (Deletes users matching a given firstName+lastName)
# -------------------------------------------------------
ac_delete_user_by_name() {
    local first="$1"
    local last="$2"
    local fullname="$first $last"
    ac_login > /dev/null 2>&1
    local users
    users=$(ac_api GET "/users" | jq -r \
        ".items[]? | select(.Name==\"$fullname\") | .Id" 2>/dev/null)
    for uid in $users; do
        ac_api DELETE "/users/$uid" > /dev/null 2>&1 && \
            echo "Deleted user $fullname (id=$uid)" || true
    done
}

# -------------------------------------------------------
# Clean up groups by name
# -------------------------------------------------------
ac_delete_group_by_name() {
    local name="$1"
    ac_login > /dev/null 2>&1
    local groups
    groups=$(ac_api GET "/groups" | jq -r \
        ".items[]? | select(.Name==\"$name\") | .Id" 2>/dev/null)
    for gid in $groups; do
        ac_api DELETE "/groups/$gid" > /dev/null 2>&1 && \
            echo "Deleted group '$name' (id=$gid)" || true
    done
}
