#!/bin/bash
# Shared utilities for Docker CLI environment tasks

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Wait for Docker daemon to be ready
wait_for_docker() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if timeout 5 docker info > /dev/null 2>&1; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "Timeout waiting for Docker daemon"
    return 1
}

# Check if a container is running
container_running() {
    local name="$1"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$name"
}

# Check if a container exists (running or stopped)
container_exists() {
    local name="$1"
    docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$name"
}

# Get container status
get_container_status() {
    local name="$1"
    docker ps -a --filter "name=^${name}$" --format '{{.Status}}' 2>/dev/null
}

# Check if an image exists locally
image_exists() {
    local image="$1"
    docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -qE "^${image}$"
}

# Get image size in MB
get_image_size_mb() {
    local image="$1"
    docker inspect "$image" --format '{{.Size}}' 2>/dev/null | awk '{printf "%.0f", $1/1048576}'
}

# Run trivy scan and return CRITICAL count
# --scanners vuln avoids secret-scan EOF failures with OCI/BuildKit images
trivy_critical_count() {
    local image="$1"
    trivy image --no-progress --severity CRITICAL --scanners vuln --format json "$image" 2>/dev/null | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for r in data.get('Results', []):
    for v in r.get('Vulnerabilities', []):
        if v.get('Severity') == 'CRITICAL':
            count += 1
print(count)
" 2>/dev/null || echo "999"
}

# Run trivy scan and return HIGH count
trivy_high_count() {
    local image="$1"
    trivy image --no-progress --severity HIGH --scanners vuln --format json "$image" 2>/dev/null | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for r in data.get('Results', []):
    for v in r.get('Vulnerabilities', []):
        if v.get('Severity') == 'HIGH':
            count += 1
print(count)
" 2>/dev/null || echo "999"
}

# Wait for a port to be open inside a container
wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if nc -z "$host" "$port" 2>/dev/null; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Check if all services in a compose project are running
compose_all_running() {
    local project_dir="$1"
    local expected_count="${2:-1}"
    local running
    running=$(docker compose -f "$project_dir/docker-compose.yml" ps --status running 2>/dev/null | grep -c "running" 2>/dev/null)
    [ -z "$running" ] && running=0
    [ "$running" -ge "$expected_count" ]
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

# Export functions
export -f take_screenshot
export -f wait_for_docker
export -f container_running
export -f container_exists
export -f get_container_status
export -f image_exists
export -f get_image_size_mb
export -f trivy_critical_count
export -f trivy_high_count
export -f wait_for_port
export -f compose_all_running
export -f json_escape
