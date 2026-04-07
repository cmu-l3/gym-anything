#!/bin/bash
# Shared utilities for HEC-RAS tasks

HECRAS_HOME="/opt/hec-ras"
MUNCIE_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
SCRIPTS_DIR="/home/ga/Documents/analysis_scripts"
XAUTHORITY_PATH="/run/user/1000/gdm/Xauthority"

# Source HEC-RAS environment
source /etc/profile.d/hec-ras.sh 2>/dev/null || true

take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    rm -f "$path"
    su - ga -c "DISPLAY=:1 XAUTHORITY=$XAUTHORITY_PATH scrot '$path'" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=$XAUTHORITY_PATH scrot "$path" 2>/dev/null || \
    DISPLAY=:1 xwd -root | convert xwd:- "$path" 2>/dev/null || true
}

kill_gedit() {
    pkill -f gedit 2>/dev/null || true
    sleep 1
    pkill -9 -f gedit 2>/dev/null || true
    sleep 1
}

kill_terminal() {
    pkill -f gnome-terminal 2>/dev/null || true
    sleep 1
}

kill_matplotlib() {
    pkill -f matplotlib 2>/dev/null || true
    pkill -f "python3.*plot" 2>/dev/null || true
    sleep 1
}

launch_gedit() {
    local filepath="$1"
    kill_gedit
    su - ga -c "DISPLAY=:1 XAUTHORITY=$XAUTHORITY_PATH setsid gedit '$filepath' > /tmp/gedit.log 2>&1 &"
    sleep 3

    # Wait for gedit window
    local timeout=15
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=$XAUTHORITY_PATH wmctrl -l 2>/dev/null | grep -qi "gedit\|text editor"; then
            echo "gedit window detected"
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    # Maximize window
    DISPLAY=:1 XAUTHORITY=$XAUTHORITY_PATH wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
}

launch_terminal() {
    local workdir="${1:-$MUNCIE_DIR}"
    kill_terminal

    # gnome-terminal needs dbus session; use dbus-launch if su fails
    su - ga -c "DISPLAY=:1 XAUTHORITY=$XAUTHORITY_PATH dbus-launch setsid gnome-terminal --working-directory='$workdir' --geometry=120x40 > /tmp/terminal.log 2>&1 &" 2>/dev/null || \
    su - ga -c "DISPLAY=:1 XAUTHORITY=$XAUTHORITY_PATH setsid gnome-terminal --working-directory='$workdir' --geometry=120x40 > /tmp/terminal.log 2>&1 &" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=$XAUTHORITY_PATH sudo -u ga gnome-terminal --working-directory="$workdir" --geometry=120x40 > /tmp/terminal.log 2>&1 &
    sleep 3

    # Wait for terminal window
    local timeout=15
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=$XAUTHORITY_PATH wmctrl -l 2>/dev/null | grep -qi "terminal\|ga@\|bash"; then
            echo "Terminal window detected"
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    # Maximize window
    DISPLAY=:1 XAUTHORITY=$XAUTHORITY_PATH wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
}

restore_muncie_project() {
    echo "Restoring Muncie project from clean copy..."
    if [ -d "$HECRAS_HOME/examples/Muncie" ]; then
        rm -rf "$MUNCIE_DIR"/*
        cp -r "$HECRAS_HOME/examples/Muncie"/* "$MUNCIE_DIR/"
        # Copy wrk_source files to working directory (input files)
        if [ -d "$MUNCIE_DIR/wrk_source" ]; then
            cp "$MUNCIE_DIR/wrk_source"/* "$MUNCIE_DIR/" 2>/dev/null || true
        fi
        chown -R ga:ga "$MUNCIE_DIR"
        echo "Muncie project restored"
        echo "Files:"
        ls -la "$MUNCIE_DIR"/*.{x04,b04,r04,hdf} 2>/dev/null || true
    else
        echo "WARNING: Clean Muncie copy not found"
    fi
}

run_simulation_if_needed() {
    # Run HEC-RAS unsteady simulation if results don't exist
    if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
        echo "Running HEC-RAS simulation to produce results..."
        source /etc/profile.d/hec-ras.sh 2>/dev/null || true
        cd "$MUNCIE_DIR"
        su - ga -c "source /etc/profile.d/hec-ras.sh; cd '$MUNCIE_DIR'; RasUnsteady Muncie.p04.tmp.hdf x04" 2>&1 | tail -5
        # Rename output
        if [ -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
            cp "$MUNCIE_DIR/Muncie.p04.tmp.hdf" "$MUNCIE_DIR/Muncie.p04.hdf"
            chown ga:ga "$MUNCIE_DIR/Muncie.p04.hdf"
            echo "Simulation complete. Results at Muncie.p04.hdf ($(du -h "$MUNCIE_DIR/Muncie.p04.hdf" | cut -f1))"
        fi
    else
        echo "Simulation results already exist at Muncie.p04.hdf"
    fi
}

type_in_terminal() {
    # Type a command into the open terminal and press Enter
    local cmd="$1"
    sleep 1
    DISPLAY=:1 XAUTHORITY=$XAUTHORITY_PATH xdotool type --delay 20 "$cmd"
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=$XAUTHORITY_PATH xdotool key Return
    sleep 2
}

wait_for_window() {
    local pattern="$1"
    local timeout="${2:-20}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=$XAUTHORITY_PATH wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}
