#!/bin/bash
# Shared helper: launch WPS Spreadsheet with a file and dismiss any remaining dialogs.
# Usage: source /workspace/scripts/launch_wps_for_task.sh
#        launch_wps_with_file "/home/ga/Documents/myfile.xlsx"
#
# This function:
#   1. Kills any existing WPS processes
#   2. Ensures X11 auth is set up
#   3. Launches WPS Spreadsheet (et) with the given file
#   4. Waits for the window to appear
#   5. Dismisses any startup dialogs (System Check, WPS Office default, etc.)
#   6. Maximizes and focuses the spreadsheet window

launch_wps_with_file() {
    local FILE_PATH="$1"
    local FILE_BASENAME=$(basename "$FILE_PATH")

    echo "Launching WPS Spreadsheet with $FILE_BASENAME..."

    # Kill any existing WPS processes
    pkill -x et 2>/dev/null || true
    pkill -f "/office6/et" 2>/dev/null || true
    sleep 2

    # Ensure X11 auth is set up
    GDM_XAUTH=$(ps aux | grep Xorg | grep -oP '(?<=-auth )\S+' | head -1)
    if [ -n "$GDM_XAUTH" ] && [ -f "$GDM_XAUTH" ]; then
        cp "$GDM_XAUTH" /home/ga/.Xauthority
        chown ga:ga /home/ga/.Xauthority
    fi

    # Launch WPS Spreadsheet
    su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; et '$FILE_PATH' &"

    # Wait for WPS window to appear (up to 30s)
    for i in $(seq 1 30); do
        if su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -l" 2>/dev/null | grep -qi "$FILE_BASENAME\|Spreadsheets"; then
            echo "WPS Spreadsheet window detected after ${i}s"
            break
        fi
        sleep 1
    done

    # Wait for dialogs to render
    sleep 3

    # Dismiss startup dialogs (retry loop, front-to-back)
    for _attempt in 1 2 3; do
        WINDOWS=$(su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -l" 2>/dev/null)

        # Close "WPS Office" default-app dialog
        WPS_DIALOG=$(echo "$WINDOWS" | grep -i "WPS Office$" | awk '{print $1}')
        if [ -n "$WPS_DIALOG" ]; then
            echo "  Dismissing 'WPS Office' dialog..."
            su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -ia '$WPS_DIALOG'" 2>/dev/null || true
            sleep 0.5
            su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; xdotool key Return" 2>/dev/null || true
            sleep 1
        fi

        # Close "System Check" dialog
        SYSCHECK_WIN=$(echo "$WINDOWS" | grep -i "System Check" | awk '{print $1}')
        if [ -n "$SYSCHECK_WIN" ]; then
            echo "  Dismissing 'System Check' dialog..."
            su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -ia '$SYSCHECK_WIN'" 2>/dev/null || true
            sleep 0.5
            su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; xdotool key alt+F4" 2>/dev/null || true
            sleep 1
        fi

        # Close "Checking completed" sub-dialog
        CHECK_WIN=$(echo "$WINDOWS" | grep -i "Checking completed" | awk '{print $1}')
        if [ -n "$CHECK_WIN" ]; then
            echo "  Dismissing 'Checking completed' dialog..."
            su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -ia '$CHECK_WIN'" 2>/dev/null || true
            sleep 0.5
            su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; xdotool key Return" 2>/dev/null || true
            sleep 1
        fi

        # Check if all dialogs are gone
        REMAINING=$(su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -l" 2>/dev/null | grep -ciE "System Check|WPS Office$|Checking completed")
        if [ "$REMAINING" -eq 0 ]; then
            break
        fi
        sleep 2
    done

    # Final fallback: Escape to close any remaining modal
    su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; xdotool key Escape" 2>/dev/null || true
    sleep 1

    # Re-focus and maximize the spreadsheet window
    WPS_WIN=$(su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -l" 2>/dev/null | grep -i "$FILE_BASENAME\|Spreadsheets" | head -1 | awk '{print $1}')
    if [ -n "$WPS_WIN" ]; then
        su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -ia '$WPS_WIN'" 2>/dev/null || true
        su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    fi

    echo "WPS Spreadsheet ready with $FILE_BASENAME"
}

# Lightweight dialog-only dismissal (no launch, no kill).
# Use when WPS is already running and you just want to ensure no dialogs are blocking.
dismiss_wps_dialogs() {
    local WINDOWS=$(su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -l" 2>/dev/null)
    local NEED_DISMISS=$(echo "$WINDOWS" | grep -ciE "System Check|WPS Office$|Checking completed")
    [ "$NEED_DISMISS" -eq 0 ] && return 0

    for _attempt in 1 2 3; do
        WINDOWS=$(su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -l" 2>/dev/null)

        WPS_DIALOG=$(echo "$WINDOWS" | grep -i "WPS Office$" | awk '{print $1}')
        if [ -n "$WPS_DIALOG" ]; then
            su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -ia '$WPS_DIALOG'" 2>/dev/null || true
            sleep 0.5
            su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; xdotool key Return" 2>/dev/null || true
            sleep 1
        fi

        SYSCHECK_WIN=$(echo "$WINDOWS" | grep -i "System Check" | awk '{print $1}')
        if [ -n "$SYSCHECK_WIN" ]; then
            su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -ia '$SYSCHECK_WIN'" 2>/dev/null || true
            sleep 0.5
            su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; xdotool key alt+F4" 2>/dev/null || true
            sleep 1
        fi

        CHECK_WIN=$(echo "$WINDOWS" | grep -i "Checking completed" | awk '{print $1}')
        if [ -n "$CHECK_WIN" ]; then
            su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -ia '$CHECK_WIN'" 2>/dev/null || true
            sleep 0.5
            su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; xdotool key Return" 2>/dev/null || true
            sleep 1
        fi

        REMAINING=$(su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -l" 2>/dev/null | grep -ciE "System Check|WPS Office$|Checking completed")
        [ "$REMAINING" -eq 0 ] && break
        sleep 1
    done

    su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; xdotool key Escape" 2>/dev/null || true
}
