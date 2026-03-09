#!/bin/bash
# Shared utilities for KStars + INDI tasks

# ── Screenshot ────────────────────────────────────────────────────────
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# ── INDI Server Management ───────────────────────────────────────────
ensure_indi_running() {
    if ! pgrep -f "indiserver" > /dev/null 2>&1; then
        echo "INDI server not running, restarting..."
        su - ga -c "bash /home/ga/start_indi.sh"
        local elapsed=0
        while [ $elapsed -lt 30 ]; do
            if ss -tlnp | grep -q ':7624'; then
                echo "INDI server restarted" >&2
                return 0
            fi
            sleep 2
            elapsed=$((elapsed + 2))
        done
        echo "WARNING: INDI server failed to restart" >&2
        return 1
    fi
    return 0
}

# ── Device Connection ─────────────────────────────────────────────────
connect_all_devices() {
    indi_setprop "Telescope Simulator.CONNECTION.CONNECT=On" 2>/dev/null || true
    sleep 1
    indi_setprop "CCD Simulator.CONNECTION.CONNECT=On" 2>/dev/null || true
    sleep 1
    indi_setprop "Focuser Simulator.CONNECTION.CONNECT=On" 2>/dev/null || true
    sleep 1
    indi_setprop "Filter Simulator.CONNECTION.CONNECT=On" 2>/dev/null || true
    sleep 1
}

is_device_connected() {
    local device="$1"
    local status
    status=$(indi_getprop -1 "${device}.CONNECTION.CONNECT" 2>/dev/null)
    [ "$status" = "On" ]
}

# ── KStars Window Management ─────────────────────────────────────────
get_kstars_window_id() {
    DISPLAY=:1 xdotool search --name "KStars" 2>/dev/null | head -1
}

ensure_kstars_running() {
    if ! pgrep -f "kstars" > /dev/null 2>&1; then
        echo "KStars not running, restarting..." >&2
        su - ga -c "bash /home/ga/start_kstars.sh"
        local elapsed=0
        while [ $elapsed -lt 60 ]; do
            if DISPLAY=:1 xdotool search --name "KStars" 2>/dev/null | head -1 | grep -q .; then
                echo "KStars restarted" >&2
                sleep 3
                return 0
            fi
            sleep 3
            elapsed=$((elapsed + 3))
        done
        echo "WARNING: KStars failed to restart" >&2
        return 1
    fi
    return 0
}

maximize_kstars() {
    DISPLAY=:1 wmctrl -r "KStars" -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

focus_kstars() {
    local wid
    wid=$(get_kstars_window_id)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null || true
    fi
}

# ── Telescope Operations ─────────────────────────────────────────────
slew_to_coordinates() {
    local ra="$1"   # RA in decimal hours
    local dec="$2"  # DEC in decimal degrees
    indi_setprop "Telescope Simulator.ON_COORD_SET.TRACK=On" 2>/dev/null || true
    indi_setprop "Telescope Simulator.EQUATORIAL_EOD_COORD.RA;DEC=${ra};${dec}" 2>/dev/null || true
}

get_telescope_position() {
    indi_getprop "Telescope Simulator.EQUATORIAL_EOD_COORD.*" 2>/dev/null
}

park_telescope() {
    indi_setprop "Telescope Simulator.TELESCOPE_PARK.PARK=On" 2>/dev/null || true
}

unpark_telescope() {
    indi_setprop "Telescope Simulator.TELESCOPE_PARK.UNPARK=On" 2>/dev/null || true
}

# ── CCD Operations ────────────────────────────────────────────────────
take_exposure() {
    local seconds="${1:-5}"
    indi_setprop "CCD Simulator.CCD_EXPOSURE.CCD_EXPOSURE_VALUE=${seconds}" 2>/dev/null || true
}

set_filter() {
    local slot="$1"  # 1-based filter slot number
    indi_setprop "Filter Simulator.FILTER_SLOT.FILTER_SLOT_VALUE=${slot}" 2>/dev/null || true
}

set_ccd_upload_dir() {
    local dir="$1"
    indi_setprop "CCD Simulator.UPLOAD_MODE.UPLOAD_LOCAL=On" 2>/dev/null || true
    indi_setprop "CCD Simulator.UPLOAD_SETTINGS.UPLOAD_DIR=${dir}" 2>/dev/null || true
}

# ── Coordinate Conversion ────────────────────────────────────────────
# Convert RA from hh:mm:ss to decimal hours
ra_hms_to_decimal() {
    local h m s
    IFS=':' read -r h m s <<< "$1"
    echo "scale=6; $h + $m/60 + $s/3600" | bc
}

# Convert DEC from dd:mm:ss to decimal degrees
dec_dms_to_decimal() {
    local d m s sign=1
    IFS=':' read -r d m s <<< "$1"
    if [[ "$d" == -* ]]; then
        sign=-1
        d="${d#-}"
    fi
    echo "scale=6; $sign * ($d + $m/60 + $s/3600)" | bc
}

# ── Wait Utilities ────────────────────────────────────────────────────
wait_for_slew_complete() {
    local timeout="${1:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local state
        state=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD._STATE" 2>/dev/null)
        if [ "$state" = "Ok" ] || [ "$state" = "Idle" ]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Slew did not complete within ${timeout}s" >&2
    return 1
}

wait_for_exposure_complete() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local val
        val=$(indi_getprop -1 "CCD Simulator.CCD_EXPOSURE.CCD_EXPOSURE_VALUE" 2>/dev/null)
        if [ "$val" = "0" ] || [ -z "$val" ]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Exposure did not complete within ${timeout}s" >&2
    return 1
}
