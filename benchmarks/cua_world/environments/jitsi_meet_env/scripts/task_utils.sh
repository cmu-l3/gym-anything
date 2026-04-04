#!/bin/bash
# Shared task utilities for Jitsi Meet environment

JITSI_BASE_URL="${JITSI_BASE_URL:-http://localhost:8080}"
FIREFOX_PROFILE="/home/ga/.mozilla/firefox/jitsi.profile"

# ── HTTP polling ─────────────────────────────────────────────────────────────
wait_for_http() {
    local url="$1"
    local timeout="${2:-120}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if curl -sfk "$url" >/dev/null 2>&1; then
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "ERROR: $url not ready after ${timeout}s"
    return 1
}

# ── Screenshot ───────────────────────────────────────────────────────────────
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# ── Display resolution ───────────────────────────────────────────────────────
display_dimensions() {
    DISPLAY=:1 xdpyinfo 2>/dev/null | grep dimensions | awk '{print $2}' || echo "1920x1080"
}

# ── Firefox control ──────────────────────────────────────────────────────────
stop_firefox() {
    pkill -f "firefox" 2>/dev/null || true
    sleep 2
    pkill -9 -f "firefox" 2>/dev/null || true
    sleep 1
    # Clear lock files
    rm -f "${FIREFOX_PROFILE}/lock" "${FIREFOX_PROFILE}/.parentlock" 2>/dev/null || true
}

get_firefox_window_id() {
    DISPLAY=:1 xdotool search --class firefox 2>/dev/null | head -1
}

focus_firefox() {
    local win_id
    win_id=$(get_firefox_window_id)
    if [ -n "$win_id" ]; then
        DISPLAY=:1 xdotool windowactivate --sync "$win_id" 2>/dev/null || true
        DISPLAY=:1 xdotool windowfocus --sync "$win_id" 2>/dev/null || true
        return 0
    fi
    # Fallback: use wmctrl
    DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
    sleep 0.5
}

navigate_to_url() {
    local url="$1"
    focus_firefox
    sleep 0.5
    DISPLAY=:1 xdotool key --clearmodifiers ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers --delay 30 "$url"
    sleep 0.3
    DISPLAY=:1 xdotool key Return
    sleep 3
}

restart_firefox() {
    local url="${1:-$JITSI_BASE_URL}"
    local wait_sec="${2:-8}"

    stop_firefox

    # NOTE: Firefox is snap-installed. Do NOT use -profile flag or su - ga -c.
    # Use nohup with DISPLAY set directly. Snap Firefox reads profiles.ini.
    DISPLAY=:1 nohup firefox "$url" >/tmp/firefox_task.log 2>&1 &
    sleep "$wait_sec"

    # Wait for Firefox window to appear
    local tries=0
    while [ $tries -lt 20 ]; do
        if get_firefox_window_id | grep -q .; then
            sleep 2
            return 0
        fi
        sleep 1
        tries=$((tries + 1))
    done
    echo "WARNING: Firefox window not detected"
    return 1
}

maximize_firefox() {
    local win_id
    win_id=$(get_firefox_window_id)
    if [ -n "$win_id" ]; then
        DISPLAY=:1 xdotool windowsize "$win_id" 1920 1080 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
}

# Join the meeting from the pre-join screen.
# Clicks the name input field and presses Enter to submit the join form.
# Resolution is 1920x1080. Name input at VG(178,375) -> actual(267,562).
join_meeting() {
    local wait_sec="${1:-12}"
    sleep 2
    # Click the name input field to focus it, then press Enter to join
    DISPLAY=:1 xdotool mousemove 267 562 click 1
    sleep 0.3
    DISPLAY=:1 xdotool key Return
    sleep "$wait_sec"
    # Move mouse to center to reveal the toolbar
    DISPLAY=:1 xdotool mousemove 960 600
    sleep 1
}
