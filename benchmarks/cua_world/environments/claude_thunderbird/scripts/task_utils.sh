#!/bin/bash
# Shared utilities for Thunderbird task setup and export scripts

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
        if wmctrl -l | grep -qi "$window_pattern"; then
            echo "✅ Window found after ${elapsed}s"
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    echo "❌ Timeout: Window not found after ${timeout}s"
    return 1
}

# Wait for a file to be created or modified
# Args: $1 - file path
#       $2 - timeout in seconds (default: 10)
# Returns: 0 if file exists and was recently modified, 1 if timeout
wait_for_file() {
    local filepath="$1"
    local timeout=${2:-10}
    local start=$(date +%s)

    echo "Waiting for file: $filepath"

    while [ $(($(date +%s) - start)) -lt $timeout ]; do
        if [ -f "$filepath" ]; then
            # Check if file was modified in the last 10 seconds
            if [ $(find "$filepath" -mmin -0.2 2>/dev/null | wc -l) -gt 0 ] || \
               [ $(($(date +%s) - start)) -lt 2 ]; then
                echo "✅ File ready: $filepath"
                return 0
            fi
        fi
        sleep 0.5
    done

    echo "⚠️ Timeout: File not updated: $filepath"
    return 1
}

# Wait for a process to start
# Args: $1 - process name pattern (pgrep pattern)
#       $2 - timeout in seconds (default: 20)
# Returns: 0 if process found, 1 if timeout
wait_for_process() {
    local process_pattern="$1"
    local timeout=${2:-20}
    local elapsed=0

    echo "Waiting for process matching '$process_pattern'..."

    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "$process_pattern" > /dev/null; then
            echo "✅ Process found after ${elapsed}s"
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    echo "❌ Timeout: Process not found after ${timeout}s"
    return 1
}

# Focus a window and verify it was focused
# Args: $1 - window ID or name pattern
# Returns: 0 if focused successfully, 1 otherwise
focus_window() {
    local window_id="$1"

    # Try to activate the window
    if wmctrl -ia "$window_id" 2>/dev/null || wmctrl -a "$window_id" 2>/dev/null; then
        sleep 0.3
        # Verify the window is now active
        if wmctrl -la | grep -q "$window_id"; then
            echo "✅ Window focused: $window_id"
            return 0
        fi
    fi

    echo "⚠️ Failed to focus window: $window_id"
    return 1
}

# Get the window ID for Thunderbird
# Returns: window ID or empty string
get_thunderbird_window_id() {
    wmctrl -l | grep -i 'Thunderbird\|Mozilla Thunderbird' | awk '{print $1; exit}'
}

# Safe xdotool command with display and user context
# Args: $1 - user (e.g., "ga")
#       $2 - display (e.g., ":1")
#       rest - xdotool arguments
safe_xdotool() {
    local user="$1"
    local display="$2"
    shift 2

    su - "$user" -c "DISPLAY=$display xdotool $*" 2>&1 | grep -v "^$"
    return ${PIPESTATUS[0]}
}

# Wait for Thunderbird to be ready (window exists and process is running)
# Args: $1 - timeout in seconds (default: 30)
# Returns: 0 if ready, 1 if timeout
wait_for_thunderbird_ready() {
    local timeout=${1:-30}

    echo "Waiting for Thunderbird to be ready..."

    # Wait for process
    if ! wait_for_process "thunderbird" $timeout; then
        return 1
    fi

    # Wait for window
    if ! wait_for_window "Thunderbird" $timeout; then
        return 1
    fi

    echo "✅ Thunderbird is ready"
    return 0
}

# Send a test email using the command line
# Args: $1 - to address
#       $2 - subject
#       $3 - body
# Returns: 0 if sent, 1 otherwise
send_test_email() {
    local to="$1"
    local subject="$2"
    local body="$3"

    echo "$body" | mail -s "$subject" "$to" 2>/dev/null
    return $?
}

# Count emails in a Thunderbird folder
# Args: $1 - folder name (default: Inbox)
#       $2 - username (default: ga)
# Returns: email count
count_emails_in_folder() {
    local folder="${1:-Inbox}"
    local username="${2:-ga}"

    thunderbird-util count --folder "$folder" --username "$username" 2>/dev/null || echo "0"
}

# Check if an email with specific subject exists
# Args: $1 - subject pattern (grep regex)
#       $2 - folder name (default: Inbox)
#       $3 - username (default: ga)
# Returns: 0 if found, 1 if not found
check_email_exists() {
    local subject_pattern="$1"
    local folder="${2:-Inbox}"
    local username="${3:-ga}"

    local emails=$(thunderbird-util list --folder "$folder" --username "$username" 2>/dev/null)
    if echo "$emails" | grep -qi "$subject_pattern"; then
        return 0
    fi
    return 1
}

# Export these functions for use in other scripts
export -f wait_for_window
export -f wait_for_file
export -f wait_for_process
export -f focus_window
export -f get_thunderbird_window_id
export -f safe_xdotool
export -f wait_for_thunderbird_ready
export -f send_test_email
export -f count_emails_in_folder
export -f check_email_exists
