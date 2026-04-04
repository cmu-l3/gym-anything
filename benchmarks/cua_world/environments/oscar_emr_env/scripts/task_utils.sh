#!/bin/bash
# Shared utilities for OSCAR EMR task setup scripts

# Function to run docker compose (supports both v1 and v2)
docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose -f /home/ga/oscar_emr/docker-compose.yml "$@"
    else
        docker-compose -f /home/ga/oscar_emr/docker-compose.yml "$@"
    fi
}

# Execute SQL query against OSCAR database (via Docker)
# Args: $1 - SQL query
# Returns: query result
oscar_query() {
    local query="$1"
    docker exec oscar-db mysql -u oscar -poscar oscar -N -e "$query" 2>/dev/null
}

# Wait for OSCAR HTTP to be reachable
# Args: $1 - timeout in seconds (default: 300)
wait_for_oscar_http() {
    local timeout=${1:-300}
    local elapsed=0
    local url="http://localhost:8080/oscar/login.do"
    echo "Waiting for OSCAR to be reachable..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "OSCAR reachable after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  Still waiting for OSCAR... ${elapsed}s (HTTP $HTTP_CODE)"
        fi
    done
    echo "WARNING: OSCAR not reachable after ${timeout}s — proceeding anyway"
    return 1
}

# Wait for a window with specified title to appear
# Args: $1 - window title pattern (grep pattern)
#       $2 - timeout in seconds (default: 30)
# Returns: 0 if found, 1 if timeout
wait_for_window() {
    local window_pattern="$1"
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for window matching '$window_pattern'..."

    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then
            echo "Window found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: Window not found after ${timeout}s"
    return 1
}

# Get the window ID for Firefox
# Returns: window ID or empty string
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla\|OSCAR' | awk '{print $1; exit}'
}

# Focus a window
# Args: $1 - window ID
focus_window() {
    local window_id="$1"
    DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null || DISPLAY=:1 wmctrl -a "$window_id" 2>/dev/null || true
    sleep 0.3
}

# Wait for a process to start
# Args: $1 - process name pattern
#       $2 - timeout in seconds (default: 20)
wait_for_process() {
    local process_pattern="$1"
    local timeout=${2:-20}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "$process_pattern" > /dev/null 2>&1; then
            echo "Process found after ${elapsed}s: $process_pattern"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: Process '$process_pattern' not found after ${timeout}s"
    return 1
}

# Take a screenshot
# Args: $1 - output file path (default: /tmp/screenshot.png)
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
    echo "Warning: Could not take screenshot"
    [ -f "$output_file" ] && echo "Screenshot saved: $output_file"
}

# Get the demographic (patient) count of active patients
get_patient_count() {
    oscar_query "SELECT COUNT(*) FROM demographic WHERE patient_status='AC'"
}

# Check if a patient exists by name
# Args: $1 - first name, $2 - last name
patient_exists() {
    local fname="$1"
    local lname="$2"
    local count
    count=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='$fname' AND last_name='$lname'")
    [ "$count" -gt 0 ]
}

# Get a patient's demographic_no by name
# Args: $1 - first name, $2 - last name
get_patient_id() {
    local fname="$1"
    local lname="$2"
    oscar_query "SELECT demographic_no FROM demographic WHERE first_name='$fname' AND last_name='$lname' LIMIT 1"
}

# Ensure Firefox is open on OSCAR login page
# Restarts Firefox if not running or not showing OSCAR
# Works from both ga user context and root context
ensure_firefox_on_oscar() {
    local OSCAR_URL="http://localhost:8080/oscar/login.jsp"

    # First ensure OSCAR is reachable
    wait_for_oscar_http 120

    # Kill any existing Firefox instances for a clean start
    pkill -f firefox 2>/dev/null || true
    sleep 3

    echo "Starting Firefox on OSCAR login page..."
    # Launch Firefox as the ga user — method depends on current user
    # Note: 'sudo -u ga nohup firefox &' fails with use_pty sudoers option
    # 'sudo su ga -s /bin/bash -c "... & disown"' properly detaches the process
    if [ "$(whoami)" = "ga" ]; then
        # Already ga user — launch directly
        DISPLAY=:1 nohup firefox "$OSCAR_URL" > /tmp/firefox_task.log 2>&1 &
        disown
    else
        # Running as root — su to ga with disown to survive shell exit
        sudo su ga -s /bin/bash -c "DISPLAY=:1 nohup firefox '$OSCAR_URL' > /tmp/firefox_task.log 2>&1 & disown"
    fi
    sleep 8

    # Wait for Firefox window
    if ! wait_for_window "firefox\|mozilla\|OSCAR" 45; then
        echo "WARNING: Firefox window not detected after 45s"
        return 1
    fi

    # Maximize window
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 1
    fi

    # Dismiss any browser dialogs (Escape)
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5

    return 0
}

# Export functions
export -f docker_compose
export -f oscar_query
export -f wait_for_oscar_http
export -f wait_for_window
export -f get_firefox_window_id
export -f focus_window
export -f wait_for_process
export -f take_screenshot
export -f get_patient_count
export -f patient_exists
export -f get_patient_id
export -f ensure_firefox_on_oscar
