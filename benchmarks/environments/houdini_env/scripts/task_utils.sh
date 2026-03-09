#!/bin/bash
# Shared utilities for Houdini tasks

# Detect HFS directory
get_hfs_dir() {
    find -L /opt -maxdepth 1 -type d -name "hfs*" | sort -V | tail -1
}

# Source Houdini environment
setup_houdini_env() {
    local hfs_dir
    hfs_dir=$(get_hfs_dir)
    if [ -n "$hfs_dir" ]; then
        export HFS="$hfs_dir"
        cd "$hfs_dir" && source houdini_setup 2>/dev/null && cd / || true
        export HOUDINI_NO_START_PAGE_SPLASH=1
        export HOUDINI_ANONYMOUS_STATISTICS=0
        export HOUDINI_NOHKEY=1
        export HOUDINI_LMINFO_VERBOSE=0
        export HOUDINI_PROMPT_ON_CRASHES=0
    fi
}

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Run hython script
run_hython_script() {
    local script="$1"
    local hfs_dir
    hfs_dir=$(get_hfs_dir)
    "$hfs_dir/bin/hython" "$script" 2>/dev/null
}

# Get scene info as JSON via hython
get_scene_info() {
    local scene_file="$1"
    local hfs_dir
    hfs_dir=$(get_hfs_dir)

    "$hfs_dir/bin/hython" -c "
import hou
import json

hou.hipFile.load('$scene_file')

nodes = []
for node in hou.node('/obj').children():
    info = {
        'name': node.name(),
        'type': node.type().name(),
    }
    if node.type().name() == 'geo':
        children = []
        for child in node.children():
            children.append({
                'name': child.name(),
                'type': child.type().name(),
            })
        info['children'] = children
    nodes.append(info)

result = {
    'filename': hou.hipFile.name(),
    'node_count': len(hou.node('/obj').children()),
    'nodes': nodes,
}
print(json.dumps(result))
" 2>/dev/null
}

# Check if Houdini is running
is_houdini_running() {
    if pgrep -f "/opt/hfs.*/bin/houdini" > /dev/null 2>&1; then
        echo "true"
    else
        echo "false"
    fi
}

# Get Houdini window info
get_houdini_window() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "houdini\|\.hipnc\|\.hip" | head -1
}

# Focus Houdini window
focus_houdini() {
    DISPLAY=:1 wmctrl -a "Houdini" 2>/dev/null || \
    DISPLAY=:1 wmctrl -a "hipnc" 2>/dev/null || \
    DISPLAY=:1 wmctrl -a "hip" 2>/dev/null || true
}

# Maximize Houdini window
maximize_houdini() {
    local window_id
    window_id=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "houdini\|\.hipnc\|\.hip" | awk '{print $1}' | head -1)
    if [ -n "$window_id" ]; then
        DISPLAY=:1 wmctrl -i -r "$window_id" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
}

# Wait for Houdini window to appear
wait_for_houdini_window() {
    local timeout=${1:-60}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "houdini\|\.hipnc\|\.hip\|untitled"; then
            echo "Houdini window found after ${elapsed}s" >&2
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "Houdini window not found within ${timeout}s" >&2
    return 1
}

# Launch Houdini with a scene file
launch_houdini() {
    local scene_file="${1:-}"
    local hfs_dir
    hfs_dir=$(get_hfs_dir)

    su - ga -c "
        export DISPLAY=:1
        export HFS='$hfs_dir'
        cd '$hfs_dir' && source houdini_setup 2>/dev/null && cd /
        export HOUDINI_NO_START_PAGE_SPLASH=1
        export HOUDINI_ANONYMOUS_STATISTICS=0
        export HOUDINI_NOHKEY=1
        export HOUDINI_LMINFO_VERBOSE=0
        export HOUDINI_PROMPT_ON_CRASHES=0
        setsid '$hfs_dir/bin/houdini' -foreground $scene_file > /tmp/houdini.log 2>&1 &
    "
}

# Kill Houdini
kill_houdini() {
    pkill -f "/opt/hfs.*/bin/houdini" 2>/dev/null || true
    sleep 2
}

# Check render output
check_render_output() {
    local output_path="$1"
    if [ -f "$output_path" ]; then
        local size
        size=$(stat -c%s "$output_path" 2>/dev/null || echo "0")
        local mime
        mime=$(file -b --mime-type "$output_path" 2>/dev/null || echo "unknown")
        echo "{\"exists\": true, \"size\": $size, \"mime_type\": \"$mime\"}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mime_type\": null}"
    fi
}
