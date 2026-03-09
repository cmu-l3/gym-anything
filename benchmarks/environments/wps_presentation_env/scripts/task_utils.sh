#!/bin/bash
# Shared utilities for WPS Presentation tasks

# Take a screenshot of the current desktop
# Uses 'import -window root' which works with GNOME compositor
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    echo "WARNING: Screenshot failed"
}

# Kill all running WPS Presentation instances
kill_wps() {
    pkill -f "/opt/kingsoft/wps-office/office6/wpp" 2>/dev/null || true
    pkill -f "wpp" 2>/dev/null || true
    sleep 2
    # Force kill if still running
    pkill -9 -f "/opt/kingsoft/wps-office/office6/wpp" 2>/dev/null || true
    sleep 1
}

# Dismiss the WPS EULA dialog if it is visible.
# Safety net in case the warm-up in setup_wps.sh did not fully accept the EULA.
# Dialog title: "Kingsoft Office Software License Agreement and Privacy Policy"
# Uses mouse clicks at verified screen coordinates (1920x1080):
#   checkbox at (645, 648), "I Confirm" button at (1290, 648)
dismiss_eula_if_present() {
    local EULA_WID=""
    EULA_WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Kingsoft Office" 2>/dev/null | head -1 || true)
    if [ -z "$EULA_WID" ]; then
        # Fallback: check wmctrl
        local WMC_LINE=""
        WMC_LINE=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "Kingsoft\|License Agreement" | head -1 || true)
        if [ -n "$WMC_LINE" ]; then
            EULA_WID=$(echo "$WMC_LINE" | awk '{print $1}')
        fi
    fi

    if [ -n "$EULA_WID" ]; then
        echo "EULA dialog detected (WID=$EULA_WID), dismissing via mouse clicks..."
        # Kill any Firefox opened alongside the EULA dialog
        pkill -f firefox 2>/dev/null || true
        sleep 1
        # Raise EULA dialog to foreground
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -ia "$EULA_WID" 2>/dev/null || true
        sleep 1
        # Click checkbox then "I Confirm" button (verified coords on 1920x1080)
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 645 648 click 1 2>/dev/null || true
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1290 648 click 1 2>/dev/null || true
        sleep 3
        echo "EULA dismissed"
        # Dismiss "Set WPS as default" dialog if it appears after EULA acceptance
        if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "WPS Office"; then
            DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1280 630 click 1 2>/dev/null || true
            sleep 2
        fi
    fi
}

# Wait for WPS Presentation window to appear
# Usage: wait_for_wps [timeout_seconds]
# Matches on the filename "performance.pptx" in the window title to avoid false-positive
# matches on the EULA dialog ("Kingsoft Office Software License Agreement...").
# Calls dismiss_eula_if_present each iteration to handle EULA appearing during launch.
wait_for_wps() {
    local timeout="${1:-60}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        # Handle EULA dialog if it appears during WPS startup
        dismiss_eula_if_present

        # Dismiss "WPS Office" format check dialog if it appears after file load
        # (appears on first PPTX open; OK button at screen (1280, 630) on 1920x1080)
        if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "WPS Office"; then
            DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1280 630 click 1 2>/dev/null || true
            sleep 1
        fi

        # Only match on the filename – guarantees the file is actually loaded
        if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "performance\.pptx"; then
            echo "WPS Presentation window found after ${elapsed}s"
            sleep 3  # Extra wait for full load
            # Final check: dismiss any lingering WPS Office dialogs
            if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "WPS Office"; then
                DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1280 630 click 1 2>/dev/null || true
                sleep 1
            fi
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: WPS Presentation window not found after ${timeout}s"
    return 1
}

# Maximize WPS Presentation window
maximize_wps() {
    sleep 1
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "WPS Presentation" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 0.5
}

# Check if WPS Presentation is running
is_wps_running() {
    pgrep -f "/opt/kingsoft/wps-office/office6/wpp" > /dev/null 2>&1
}

# Launch WPS Presentation with a specific file
# Usage: launch_wps_with_file /path/to/file.pptx
launch_wps_with_file() {
    local filepath="$1"
    su - ga -c "DISPLAY=:1 wpp \"$filepath\" > /tmp/wpp_task.log 2>&1 &"
}

# Reset presentation file from original (ensures clean state for each task run)
# Usage: reset_presentation
reset_presentation() {
    mkdir -p /home/ga/Documents/presentations
    cp /opt/wps_samples/performance.pptx /home/ga/Documents/presentations/performance.pptx
    chown ga:ga /home/ga/Documents/presentations/performance.pptx
    # Remove any previously generated output files
    rm -f /home/ga/Documents/presentations/performance_output.pdf
    echo "Presentation file reset to original state"
}
