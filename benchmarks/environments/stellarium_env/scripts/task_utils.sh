#!/bin/bash
# Shared utilities for Stellarium tasks

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# ── Screenshot functions ─────────────────────────────────────────────

take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# ── Window management ────────────────────────────────────────────────

get_stellarium_window_id() {
    DISPLAY=:1 xdotool search --name "Stellarium" 2>/dev/null | head -1
}

ensure_stellarium_running() {
    if ! pgrep -x "stellarium" > /dev/null 2>&1; then
        echo "Stellarium not running, starting..."
        su - ga -c "bash /home/ga/start_stellarium.sh"
        # Wait for window (llvmpipe software rendering is slow, allow 90s)
        local elapsed=0
        while [ $elapsed -lt 90 ]; do
            WID=$(get_stellarium_window_id)
            if [ -n "$WID" ]; then
                echo "Stellarium window found"
                return 0
            fi
            sleep 3
            elapsed=$((elapsed + 3))
        done
        echo "WARNING: Stellarium window not found within 90s"
    fi
}

maximize_stellarium() {
    DISPLAY=:1 wmctrl -r "Stellarium" -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

focus_stellarium() {
    local wid=$(get_stellarium_window_id)
    if [ -n "$wid" ]; then
        DISPLAY=:1 xdotool windowactivate "$wid" 2>/dev/null || true
        DISPLAY=:1 xdotool windowfocus "$wid" 2>/dev/null || true
    fi
}

# ── Stellarium keyboard shortcuts ────────────────────────────────────
# These correspond to Stellarium's built-in keyboard shortcuts

toggle_constellation_lines() {
    focus_stellarium
    DISPLAY=:1 xdotool key c 2>/dev/null || true
}

toggle_constellation_names() {
    focus_stellarium
    DISPLAY=:1 xdotool key v 2>/dev/null || true
}

toggle_constellation_art() {
    focus_stellarium
    DISPLAY=:1 xdotool key r 2>/dev/null || true
}

toggle_atmosphere() {
    focus_stellarium
    DISPLAY=:1 xdotool key a 2>/dev/null || true
}

toggle_ground() {
    focus_stellarium
    DISPLAY=:1 xdotool key g 2>/dev/null || true
}

toggle_equatorial_grid() {
    focus_stellarium
    DISPLAY=:1 xdotool key e 2>/dev/null || true
}

toggle_azimuthal_grid() {
    focus_stellarium
    DISPLAY=:1 xdotool key z 2>/dev/null || true
}

toggle_cardinal_points() {
    focus_stellarium
    DISPLAY=:1 xdotool key q 2>/dev/null || true
}

toggle_nebulae() {
    focus_stellarium
    DISPLAY=:1 xdotool key n 2>/dev/null || true
}

toggle_planet_labels() {
    focus_stellarium
    DISPLAY=:1 xdotool key p 2>/dev/null || true
}

# Open search dialog (Ctrl+F or F3)
open_search_dialog() {
    focus_stellarium
    DISPLAY=:1 xdotool key ctrl+f 2>/dev/null || true
    sleep 1
}

# Open location dialog (F6)
open_location_dialog() {
    focus_stellarium
    DISPLAY=:1 xdotool key F6 2>/dev/null || true
    sleep 1
}

# Open date/time dialog (F5)
open_datetime_dialog() {
    focus_stellarium
    DISPLAY=:1 xdotool key F5 2>/dev/null || true
    sleep 1
}

# Open sky/viewing options (F4)
open_sky_options() {
    focus_stellarium
    DISPLAY=:1 xdotool key F4 2>/dev/null || true
    sleep 1
}

# Open configuration dialog (F2)
open_config_dialog() {
    focus_stellarium
    DISPLAY=:1 xdotool key F2 2>/dev/null || true
    sleep 1
}

# Zoom in/out
zoom_in() {
    focus_stellarium
    DISPLAY=:1 xdotool key Page_Up 2>/dev/null || true
}

zoom_out() {
    focus_stellarium
    DISPLAY=:1 xdotool key Page_Down 2>/dev/null || true
}

# Reset to default view (center on zenith)
reset_view() {
    focus_stellarium
    DISPLAY=:1 xdotool key ctrl+shift+h 2>/dev/null || true
}

# Take Stellarium screenshot (Ctrl+S)
stellarium_screenshot() {
    focus_stellarium
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 1
}

# ── Process management ───────────────────────────────────────────────

kill_stellarium() {
    pkill stellarium 2>/dev/null || true
    sleep 2
    pkill -9 stellarium 2>/dev/null || true
}

restart_stellarium() {
    kill_stellarium
    sleep 3
    su - ga -c "bash /home/ga/start_stellarium.sh"
    sleep 10
    ensure_stellarium_running
}
