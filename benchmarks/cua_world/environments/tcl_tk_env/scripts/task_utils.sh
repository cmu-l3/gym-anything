#!/bin/bash
# Shared utilities for Tcl/Tk tasks

take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || true
}

kill_wish() {
    pkill -f "wish8.6" 2>/dev/null || true
    pkill -f "wish" 2>/dev/null || true
    sleep 2
}

kill_gedit() {
    pkill -f "gedit" 2>/dev/null || true
    sleep 2
}

kill_all_apps() {
    kill_wish
    kill_gedit
    pkill -f "xterm" 2>/dev/null || true
    pkill -f "gnome-terminal" 2>/dev/null || true
    sleep 1
}

launch_gedit() {
    local file_path="$1"
    if [ "$(whoami)" = "root" ]; then
        setsid su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority gedit '$file_path' &" > /tmp/gedit.log 2>&1
    else
        setsid DISPLAY=:1 gedit "$file_path" > /tmp/gedit.log 2>&1 &
    fi
    # Wait for gedit window to appear
    local timeout=30
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "gedit"; then
            echo "gedit window ready"
            sleep 2
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: gedit window did not appear within ${timeout}s"
    return 0
}

launch_terminal() {
    local start_dir="${1:-/home/ga/Documents}"
    if [ "$(whoami)" = "root" ]; then
        setsid su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xterm -fa 'Monospace' -fs 12 -bg black -fg white -e 'cd $start_dir; exec bash' &" > /tmp/terminal.log 2>&1
    else
        setsid DISPLAY=:1 xterm -fa 'Monospace' -fs 12 -bg black -fg white -e "cd $start_dir; exec bash" > /tmp/terminal.log 2>&1 &
    fi
    local timeout=20
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "xterm\|ga@\|bash"; then
            echo "Terminal window ready"
            sleep 2
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Terminal window did not appear within ${timeout}s"
    return 0
}

maximize_window() {
    local window_name="$1"
    sleep 1
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "$window_name" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
}

focus_window() {
    local window_name="$1"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a "$window_name" 2>/dev/null || true
    sleep 1
}
