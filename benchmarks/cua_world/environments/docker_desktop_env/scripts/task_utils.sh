#!/bin/bash
# Shared utilities for Docker Desktop tasks

# Auto-detect Docker Desktop socket and use it if available.
# This ensures root and ga user both talk to the same Docker daemon
# (Docker Desktop's daemon), so that containers/images created via the GUI
# are visible to scripts and verifiers running as root.
if [ -S /home/ga/.docker/desktop/docker.sock ]; then
    export DOCKER_HOST="unix:///home/ga/.docker/desktop/docker.sock"
fi

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Get container count
get_container_count() {
    local running="${1:-all}"  # "running" or "all"
    if [ "$running" = "running" ]; then
        timeout 5 docker ps -q 2>/dev/null | wc -l
    else
        timeout 5 docker ps -aq 2>/dev/null | wc -l
    fi
}

# Get image count
get_image_count() {
    timeout 5 docker images -q 2>/dev/null | wc -l
}

# Check if a specific container exists
container_exists() {
    local name="$1"
    timeout 5 docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$name"
}

# Check if a specific container is running
container_running() {
    local name="$1"
    timeout 5 docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$name"
}

# Check if a specific image exists
image_exists() {
    local image="$1"
    timeout 5 docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -qE "^${image}(:latest)?$"
}

# Get container details as JSON
get_container_json() {
    local name="$1"
    timeout 5 docker inspect "$name" 2>/dev/null || echo "{}"
}

# Get container status
get_container_status() {
    local name="$1"
    timeout 5 docker ps -a --filter "name=^${name}$" --format '{{.Status}}' 2>/dev/null
}

# Check if Docker Desktop is running
docker_desktop_running() {
    pgrep -f "com.docker.backend" > /dev/null 2>&1 || \
    pgrep -f "/opt/docker-desktop/Docker" > /dev/null 2>&1
}

# Check if Docker daemon is ready
docker_daemon_ready() {
    timeout 5 docker info > /dev/null 2>&1
}

# Wait for Docker daemon to be ready (with timeout)
wait_for_docker_daemon() {
    local timeout_sec="${1:-60}"
    local elapsed=0
    echo "Waiting for Docker daemon (timeout: ${timeout_sec}s)..." >&2
    while [ $elapsed -lt $timeout_sec ]; do
        if timeout 5 docker info > /dev/null 2>&1; then
            echo "Docker daemon is ready" >&2
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        if [ $((elapsed % 10)) -eq 0 ]; then
            echo "  Waiting... (${elapsed}s)" >&2
        fi
    done
    echo "Timeout waiting for Docker daemon" >&2
    return 1
}

# Focus Docker Desktop window
focus_docker_desktop() {
    local wid=$(DISPLAY=:1 wmctrl -l | grep -i "docker" | head -1 | awk '{print $1}')
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null
        return 0
    fi
    return 1
}

# Create result JSON with proper escaping
create_result_json() {
    local temp_file=$(mktemp /tmp/result.XXXXXX.json)
    cat > "$temp_file"

    # Move to final location with fallbacks
    rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
    cp "$temp_file" /tmp/task_result.json 2>/dev/null || sudo cp "$temp_file" /tmp/task_result.json
    chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
    rm -f "$temp_file"
}

# Escape string for JSON
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}
