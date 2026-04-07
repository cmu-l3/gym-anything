#!/bin/bash
# Shared utilities for all Anaconda Navigator tasks

# Screenshot function (runs as ga if invoked as root)
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    if [ "$(whoami)" = "root" ]; then
        su - ga -c "DISPLAY=:1 scrot '$path'" 2>/dev/null || \
        su - ga -c "DISPLAY=:1 import -window root '$path'" 2>/dev/null || true
    else
        DISPLAY=:1 scrot "$path" 2>/dev/null || \
        DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    fi
}

# Wait for Anaconda Navigator to be running
wait_for_navigator() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "navigator\|anaconda"; then
            echo "Anaconda Navigator is running"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Navigator not detected within ${timeout}s"
    return 1
}

# Focus Navigator window (runs as ga if invoked as root)
focus_navigator_window() {
    if [ "$(whoami)" = "root" ]; then
        local WID=$(su - ga -c "DISPLAY=:1 wmctrl -l" 2>/dev/null | grep -i "navigator\|anaconda" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            su - ga -c "DISPLAY=:1 wmctrl -ia $WID" 2>/dev/null || true
            su - ga -c "DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz" 2>/dev/null || true
            echo "Navigator window focused and maximized"
            return 0
        fi
    else
        local WID=$(DISPLAY=:1 wmctrl -l | grep -i "navigator\|anaconda" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
            DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
            echo "Navigator window focused and maximized"
            return 0
        fi
    fi
    echo "WARNING: No Navigator window found to focus"
    return 1
}

# Dismiss dialogs by pressing Escape (runs as ga if invoked as root)
dismiss_dialogs() {
    local count="${1:-3}"
    for i in $(seq 1 $count); do
        if [ "$(whoami)" = "root" ]; then
            su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
        else
            DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        fi
        sleep 1
    done
}

# Check if a conda environment exists
conda_env_exists() {
    local env_name="$1"
    su - ga -c "/home/ga/anaconda3/bin/conda env list" 2>/dev/null | grep -q "^${env_name} "
}

# Check if a package is installed in an environment
package_installed_in_env() {
    local env_name="$1"
    local package_name="$2"
    su - ga -c "/home/ga/anaconda3/bin/conda list -n ${env_name}" 2>/dev/null | grep -q "^${package_name} "
}

# Wait for Jupyter to be running
wait_for_jupyter() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if curl -s http://localhost:8888/ > /dev/null 2>&1; then
            echo "Jupyter is running"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Jupyter not detected within ${timeout}s"
    return 1
}

# Launch Navigator on a specific tab
# IMPORTANT: Navigator sidebar uses Qt Quick/QML rendering which does NOT respond
# to programmatic mouse clicks (pyautogui, xdotool, XTest, evdev).
# The only reliable method is launching Navigator with GA_NAV_DEFAULT_TAB env var
# (set via source code patch in install_anaconda.sh).
navigate_to_tab() {
    local tab_name="$1"
    echo "Launching Navigator on $tab_name tab..."

    # Kill any existing Navigator (post_start doesn't launch it, but be safe)
    pkill -f anaconda-navigator 2>/dev/null || true
    sleep 3

    # Launch Navigator with the desired default tab
    su - ga -c "DISPLAY=:1 GA_NAV_DEFAULT_TAB=$tab_name setsid /home/ga/anaconda3/bin/anaconda-navigator > /tmp/navigator_startup.log 2>&1 &"
    sleep 2

    # Wait for Navigator's main window (not just splash screen)
    echo "Waiting for Navigator to fully load..."
    local timeout=180
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        # Check for the MAIN window title "Anaconda Navigator" (not splash "Anaconda-Navigator")
        if su - ga -c "DISPLAY=:1 wmctrl -l" 2>/dev/null | grep -q "Anaconda Navigator"; then
            echo "Navigator main window detected after ${elapsed}s"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    if [ $elapsed -ge $timeout ]; then
        echo "WARNING: Navigator main window not detected within ${timeout}s"
        cat /tmp/navigator_startup.log 2>/dev/null | tail -10
    fi

    # Wait for tab content to finish loading
    sleep 8

    # Focus and maximize
    focus_navigator_window
    sleep 2

    # Dismiss any startup dialogs
    dismiss_dialogs 2

    echo "Navigator launched on $tab_name tab"
}

# Restart Navigator if needed
restart_navigator() {
    # Kill any existing Navigator processes
    pkill -f anaconda-navigator 2>/dev/null || true
    sleep 2

    # Relaunch
    su - ga -c "DISPLAY=:1 setsid /home/ga/anaconda3/bin/anaconda-navigator > /tmp/navigator_startup.log 2>&1 &"
    sleep 2

    # Wait for it
    wait_for_navigator 90
}
