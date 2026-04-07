#!/bin/bash
# Shared utilities for all Autopsy tasks

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Safe JSON write: temp file first, then move with permission handling
safe_json_write() {
    local json_content="$1"
    local target_path="$2"

    TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
    echo "$json_content" > "$TEMP_JSON"

    rm -f "$target_path" 2>/dev/null || sudo rm -f "$target_path" 2>/dev/null || true
    cp "$TEMP_JSON" "$target_path" 2>/dev/null || sudo cp "$TEMP_JSON" "$target_path"
    chmod 666 "$target_path" 2>/dev/null || sudo chmod 666 "$target_path" 2>/dev/null || true
    rm -f "$TEMP_JSON"
}

# Wait for Autopsy window to appear
wait_for_autopsy_window() {
    local timeout="${1:-180}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "autopsy\|welcome\|sleuthkit"; then
            echo "Autopsy window detected after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "WARNING: Autopsy window not found within ${timeout}s"
    return 1
}

# Check if Autopsy is running
is_autopsy_running() {
    pgrep -f "/opt/autopsy" 2>/dev/null | head -1 || echo "0"
}

# Kill any running Autopsy instances (including Solr child processes)
kill_autopsy() {
    pkill -f "/opt/autopsy" 2>/dev/null || true
    sleep 2
    pkill -9 -f "/opt/autopsy" 2>/dev/null || true
    pkill -9 -f "java.*netbeans" 2>/dev/null || true
    pkill -9 -f "solr" 2>/dev/null || true
    sleep 1
    # Clean Solr lock files to prevent "Unable to connect to Solr" on next launch
    find /home/ga/.autopsy -name "write.lock" -delete 2>/dev/null || true
    rm -f /home/ga/.autopsy/dev/var/log/autopsy.log.0.lck 2>/dev/null || true
}

# Find Autopsy install directory
find_autopsy_dir() {
    find /opt -maxdepth 1 -type d -name 'autopsy*' 2>/dev/null | head -1
}

# Launch Autopsy as ga user with LIMITED memory to prevent OOM
launch_autopsy() {
    local autopsy_dir
    autopsy_dir=$(find_autopsy_dir)
    local java_home
    java_home=$(find /usr/lib/jvm -maxdepth 1 -type d -name 'java-17*' 2>/dev/null | head -1)

    # CRITICAL: Limit JVM heap to 2g to prevent OOM killing the VM
    # Autopsy defaults to 4g+ which can crash an 8-12GB VM
    su - ga -c "DISPLAY=:1 JAVA_HOME=$java_home setsid $autopsy_dir/bin/autopsy -J-Xmx2g -J-Xms256m > /tmp/autopsy_task.log 2>&1 &"
}

# Get info about a disk image using TSK
get_image_info() {
    local image_path="$1"
    img_stat "$image_path" 2>/dev/null || echo "Could not read image info"
}

# List files in a disk image using TSK
list_image_files() {
    local image_path="$1"
    fls -r "$image_path" 2>/dev/null || echo "Could not list files"
}
