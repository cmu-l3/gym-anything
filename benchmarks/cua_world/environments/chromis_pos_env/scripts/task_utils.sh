#!/bin/bash
# Shared utilities for Chromis POS tasks

export DISPLAY=:1
export XAUTHORITY=/run/user/1000/gdm/Xauthority
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

# ── Screenshot ───────────────────────────────────────────────────────────────
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root "$path" 2>/dev/null || true
}

# ── Launch Chromis POS ───────────────────────────────────────────────────────
launch_chromis() {
    echo "Launching Chromis POS..."
    # Kill any existing instances
    pkill -f "chromispos\|ChromisPOS" 2>/dev/null || true
    pkill -f "java.*chromis" 2>/dev/null || true
    sleep 2

    su - ga -c "setsid bash -c 'export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; cd /opt/chromispos; /usr/local/bin/launch-chromispos > /tmp/chromis_task.log 2>&1' &"
}

# ── Wait for Chromis POS window ──────────────────────────────────────────────
wait_for_chromis() {
    local timeout="${1:-90}"
    local elapsed=0
    echo "Waiting for Chromis POS window (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "chromis\|unicenta\|pos\|login\|java\|FocusProxy"; then
            echo "Chromis POS window detected at ${elapsed}s"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "WARNING: Chromis POS window not detected after ${timeout}s"
    return 1
}

# ── Focus Chromis POS window ─────────────────────────────────────────────────
focus_chromis() {
    local WID
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "chromis\|unicenta\|pos\|login\|java\|FocusProxy" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
    fi
    # Also try by class pattern
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "Chromis" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "POS" 2>/dev/null || true
}

# ── Maximize Chromis POS window ──────────────────────────────────────────────
maximize_chromis() {
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

# ── Dismiss dialogs ──────────────────────────────────────────────────────────
dismiss_dialogs() {
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return 2>/dev/null || true
    sleep 1
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return 2>/dev/null || true
}

# ── Kill Chromis POS ─────────────────────────────────────────────────────────
kill_chromis() {
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key alt+F4 2>/dev/null || true
    sleep 2
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return 2>/dev/null || true
    sleep 3
    pkill -f "chromispos\|ChromisPOS" 2>/dev/null || true
    pkill -f "java.*chromis" 2>/dev/null || true
    sleep 2
}

# ── Database query helper ────────────────────────────────────────────────────
chromis_query() {
    local query="$1"
    mysql -u root chromispos -N -e "$query" 2>/dev/null
}

# ── Ensure MariaDB is running ────────────────────────────────────────────────
ensure_mariadb() {
    systemctl start mariadb 2>/dev/null || true
    local timeout=30
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if mysqladmin ping -h localhost 2>/dev/null | grep -q "alive"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}
