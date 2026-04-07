#!/bin/bash
# Shared utility functions for CoppeliaSim tasks

export DISPLAY=:1
export COPPELIASIM_ROOT_DIR=/opt/CoppeliaSim
export LD_LIBRARY_PATH="/opt/CoppeliaSim:${LD_LIBRARY_PATH:-}"
export QT_QPA_PLATFORM_PLUGIN_PATH="/opt/CoppeliaSim"
export LIBGL_ALWAYS_SOFTWARE=1

# ─── Screenshot ──────────────────────────────────────────────────────────────

take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# ─── Process management ─────────────────────────────────────────────────────

is_coppeliasim_running() {
    if pgrep -f "coppeliaSim" > /dev/null 2>&1; then
        echo "true"
    else
        echo "false"
    fi
}

kill_coppeliasim() {
    # Kill CoppeliaSim and its helper processes (pythonLauncher, addons)
    pkill -f coppeliaSim 2>/dev/null || true
    pkill -f pythonLauncher 2>/dev/null || true
    sleep 2
    pkill -9 -f coppeliaSim 2>/dev/null || true
    pkill -9 -f pythonLauncher 2>/dev/null || true
    sleep 1
}

launch_coppeliasim() {
    local scene_file="${1:-}"
    kill_coppeliasim

    if [ -n "$scene_file" ]; then
        su - ga -c "
            export DISPLAY=:1
            export COPPELIASIM_ROOT_DIR=/opt/CoppeliaSim
            export LD_LIBRARY_PATH=/opt/CoppeliaSim:\${LD_LIBRARY_PATH:-}
            export QT_QPA_PLATFORM_PLUGIN_PATH=/opt/CoppeliaSim
            export LIBGL_ALWAYS_SOFTWARE=1
            cd /opt/CoppeliaSim
            setsid ./coppeliaSim.sh '$scene_file' > /tmp/coppeliasim.log 2>&1 &
        " &
    else
        su - ga -c "
            export DISPLAY=:1
            export COPPELIASIM_ROOT_DIR=/opt/CoppeliaSim
            export LD_LIBRARY_PATH=/opt/CoppeliaSim:\${LD_LIBRARY_PATH:-}
            export QT_QPA_PLATFORM_PLUGIN_PATH=/opt/CoppeliaSim
            export LIBGL_ALWAYS_SOFTWARE=1
            cd /opt/CoppeliaSim
            setsid ./coppeliaSim.sh > /tmp/coppeliasim.log 2>&1 &
        " &
    fi

    # Wait for CoppeliaSim window to appear
    for i in $(seq 1 30); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "coppelia"; then
            echo "CoppeliaSim window detected after ${i}s"
            sleep 3  # Extra settle time
            return 0
        fi
        sleep 1
    done
    echo "WARNING: CoppeliaSim window not detected after 30s"
    return 1
}

focus_coppeliasim() {
    DISPLAY=:1 wmctrl -a "CoppeliaSim" 2>/dev/null || \
    DISPLAY=:1 wmctrl -a "coppelia" 2>/dev/null || true
    sleep 0.5
}

maximize_coppeliasim() {
    local wid
    wid=$(DISPLAY=:1 xdotool search --name "CoppeliaSim" 2>/dev/null | head -1)
    if [ -n "$wid" ]; then
        DISPLAY=:1 xdotool windowactivate "$wid" 2>/dev/null || true
        DISPLAY=:1 xdotool windowsize "$wid" 1920 1080 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
}

# ─── File utilities ──────────────────────────────────────────────────────────

get_file_size() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        stat -c %s "$filepath" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

get_file_mtime() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        stat -c %Y "$filepath" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# ─── JSON helpers ────────────────────────────────────────────────────────────

json_bool() {
    local val="$1"
    case "${val,,}" in
        true|yes|1) echo "true" ;;
        *) echo "false" ;;
    esac
}

create_result_json() {
    local temp_file
    temp_file=$(mktemp /tmp/result.XXXXXX.json)
    cat > "$temp_file"
    rm -f /tmp/task_result.json 2>/dev/null || true
    cp "$temp_file" /tmp/task_result.json 2>/dev/null || sudo cp "$temp_file" /tmp/task_result.json
    chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
    rm -f "$temp_file"
}

# ─── CoppeliaSim scene utilities ─────────────────────────────────────────────

list_scene_files() {
    find /opt/CoppeliaSim/scenes -name "*.ttt" 2>/dev/null
}

list_robot_models() {
    find /opt/CoppeliaSim/models/robots -name "*.ttm" 2>/dev/null
}

# Check if simulation is running by looking at window title
is_simulation_running() {
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "simulation.*running\|started"; then
        echo "true"
    else
        echo "false"
    fi
}

# Dismiss any popup dialogs by pressing Escape or Enter
dismiss_dialogs() {
    # Dismiss CoppeliaSim-specific "Welcome" language dialog
    local welcome_wid
    welcome_wid=$(DISPLAY=:1 xdotool search --name "Welcome to CoppeliaSim" 2>/dev/null | head -1)
    if [ -n "$welcome_wid" ]; then
        echo "Dismissing Welcome dialog..." >&2
        DISPLAY=:1 xdotool windowactivate "$welcome_wid" 2>/dev/null || true
        sleep 0.3
        # Click "Set up for Lua" button area (dialog at ~731,448 size 531x324)
        DISPLAY=:1 xdotool mousemove 867 675 click 1 2>/dev/null || true
        sleep 1
        # Verify dismissed
        local still_there
        still_there=$(DISPLAY=:1 xdotool search --name "Welcome to CoppeliaSim" 2>/dev/null | head -1)
        if [ -n "$still_there" ]; then
            DISPLAY=:1 xdotool key Return 2>/dev/null || true
            sleep 0.5
        fi
    fi

    # Dismiss generic dialogs
    for dialog_name in "Warning" "Error" "Info" "Message" "Tip" "Welcome"; do
        local dlg_wid
        dlg_wid=$(DISPLAY=:1 xdotool search --name "$dialog_name" 2>/dev/null | head -1)
        if [ -n "$dlg_wid" ]; then
            DISPLAY=:1 xdotool windowactivate "$dlg_wid" 2>/dev/null || true
            sleep 0.3
            DISPLAY=:1 xdotool key Escape 2>/dev/null || true
            sleep 0.3
        fi
    done
}

# ─── ZMQ Remote API ──────────────────────────────────────────────────────────

# Check if ZMQ remote API is responding
check_zmq_api() {
    python3 -c "
import zmq, sys
ctx = zmq.Context()
s = ctx.socket(zmq.REQ)
s.setsockopt(zmq.RCVTIMEO, 3000)
s.setsockopt(zmq.SNDTIMEO, 3000)
try:
    s.connect('tcp://localhost:23000')
    print('connected')
    sys.exit(0)
except:
    sys.exit(1)
finally:
    s.close()
    ctx.term()
" 2>/dev/null && echo "true" || echo "false"
}

# Get scene object count via ZMQ API
get_scene_object_count() {
    python3 -c "
import sys
sys.path.insert(0, '/opt/CoppeliaSim/programming/zmqRemoteApi/clients/python')
from coppeliasim_zmqremoteapi_client import RemoteAPIClient
try:
    client = RemoteAPIClient()
    sim = client.require('sim')
    handles = sim.getObjects(0, sim.handle_all)
    print(len(handles))
except Exception as e:
    print('0')
" 2>/dev/null || echo "0"
}
