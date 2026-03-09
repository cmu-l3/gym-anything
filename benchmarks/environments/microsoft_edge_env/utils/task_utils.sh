#!/bin/bash
# Shared utility functions for Microsoft Edge tasks

# Kill Edge for a user
kill_edge() {
    local username=${1:-ga}
    echo "Killing Microsoft Edge for user: $username"
    pkill -u "$username" -f microsoft-edge 2>/dev/null || true
    pkill -u "$username" -f msedge 2>/dev/null || true
    sleep 2
    pkill -9 -u "$username" -f microsoft-edge 2>/dev/null || true
    pkill -9 -u "$username" -f msedge 2>/dev/null || true
    sleep 1
}

# Wait for a process to start
wait_for_process() {
    local process_name=$1
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for $process_name process (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "$process_name" > /dev/null; then
            echo "$process_name process found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Timeout waiting for $process_name process"
    return 1
}

# Wait for a window to appear
wait_for_window() {
    local window_name=$1
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for window matching '$window_name' (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "$window_name"; then
            echo "Window found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Timeout waiting for window '$window_name'"
    return 1
}

# Get Edge window ID
get_edge_window_id() {
    DISPLAY=:1 wmctrl -l | grep -i "edge\|microsoft" | head -1 | awk '{print $1}'
}

# Focus a window by ID
focus_window() {
    local window_id=$1
    if [ -n "$window_id" ]; then
        DISPLAY=:1 wmctrl -i -a "$window_id" 2>/dev/null
        sleep 0.5
    fi
}

# Take screenshot
take_screenshot() {
    local output_path=${1:-/tmp/screenshot.png}
    DISPLAY=:1 scrot "$output_path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$output_path" 2>/dev/null || true
}

# Get Edge profile path
get_profile_path() {
    local username=${1:-ga}
    echo "/home/$username/.config/microsoft-edge/Default"
}

# Check if Bookmarks file exists
check_bookmarks_file() {
    local username=${1:-ga}
    local bookmarks_file="/home/$username/.config/microsoft-edge/Default/Bookmarks"
    if [ -f "$bookmarks_file" ]; then
        echo "$bookmarks_file"
        return 0
    else
        echo ""
        return 1
    fi
}

# Parse Edge bookmarks JSON file
get_edge_bookmarks() {
    local bookmarks_file=${1:-"/home/ga/.config/microsoft-edge/Default/Bookmarks"}

    if [ ! -f "$bookmarks_file" ]; then
        echo ""
        return 1
    fi

    python3 << PYEOF
import json
import sys

try:
    with open("$bookmarks_file", 'r') as f:
        data = json.load(f)

    def extract_bookmarks(node, path=''):
        results = []
        if node.get('type') == 'url':
            results.append({
                'name': node.get('name', ''),
                'url': node.get('url', ''),
                'folder': path
            })
        elif node.get('type') == 'folder':
            new_path = path + '/' + node.get('name', '') if path else node.get('name', '')
            for child in node.get('children', []):
                results.extend(extract_bookmarks(child, new_path))
        return results

    roots = data.get('roots', {})
    all_bookmarks = []
    for root_name, root_node in roots.items():
        if isinstance(root_node, dict):
            all_bookmarks.extend(extract_bookmarks(root_node, root_name))

    print(json.dumps(all_bookmarks))
except Exception as e:
    print(json.dumps([]))
PYEOF
}

# Query Edge history (requires closing Edge or copying DB)
query_edge_history() {
    local limit=${1:-10}
    local history_db="/home/ga/.config/microsoft-edge/Default/History"

    if [ ! -f "$history_db" ]; then
        echo "No history database found"
        return 1
    fi

    # Copy to avoid lock issues
    local temp_db="/tmp/edge_history_copy_$$.db"
    cp "$history_db" "$temp_db" 2>/dev/null

    if [ -f "$temp_db" ]; then
        sqlite3 "$temp_db" "SELECT url, title, datetime(last_visit_time/1000000-11644473600, 'unixepoch') as visit_time FROM urls ORDER BY last_visit_time DESC LIMIT $limit;" 2>/dev/null
        rm -f "$temp_db"
    fi
}

# Launch Edge with standard flags
launch_edge() {
    local url=${1:-}
    local username=${2:-ga}

    su - "$username" -c "DISPLAY=:1 microsoft-edge \
        --no-first-run \
        --no-default-browser-check \
        --disable-sync \
        --disable-features=TranslateUI \
        --disable-extensions \
        --disable-component-update \
        --disable-background-networking \
        --disable-client-side-phishing-detection \
        --disable-default-apps \
        --disable-infobars \
        --password-store=basic \
        $url > /tmp/edge.log 2>&1 &"
}
