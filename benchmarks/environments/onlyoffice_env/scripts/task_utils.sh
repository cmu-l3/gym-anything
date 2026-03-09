#!/bin/bash
# Shared utilities for ONLYOFFICE task setup and export scripts

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

# Check if ONLYOFFICE is running
# Returns: 0 if running, 1 if not
is_onlyoffice_running() {
    pgrep -f "onlyoffice-desktopeditors|DesktopEditors" > /dev/null
    return $?
}

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom() {
    if command -v onlyoffice-oom-protect &> /dev/null; then
        onlyoffice-oom-protect
    fi
}

# Kill all ONLYOFFICE processes for a user
# Args: $1 - username
kill_onlyoffice() {
    local username=$1

    echo "Killing ONLYOFFICE processes for user: $username"

    # Get PIDs of ONLYOFFICE processes owned by the user
    local pids=$(pgrep -u $username -f "onlyoffice-desktopeditors|DesktopEditors")

    if [ -n "$pids" ]; then
        for pid in $pids; do
            kill -TERM $pid 2>/dev/null || true
        done
        sleep 2

        # Force kill if still running
        pids=$(pgrep -u $username -f "onlyoffice-desktopeditors|DesktopEditors")
        if [ -n "$pids" ]; then
            for pid in $pids; do
                kill -KILL $pid 2>/dev/null || true
            done
        fi
        echo "✅ ONLYOFFICE processes terminated"
    else
        echo "ℹ️  No ONLYOFFICE processes found"
    fi
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
        if wmctrl -lpG | grep -q "$window_id"; then
            echo "✅ Window focused: $window_id"
            return 0
        fi
    fi

    echo "⚠️ Failed to focus window: $window_id"
    return 1
}

# Get the window ID for ONLYOFFICE
# Returns: window ID or empty string
get_onlyoffice_window_id() {
    wmctrl -l | grep -i 'ONLYOFFICE\|Desktop Editors' | awk '{print $1; exit}'
}

# Focus ONLYOFFICE window
focus_onlyoffice_window() {
    local wid=$(get_onlyoffice_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
        return $?
    else
        echo "⚠️ ONLYOFFICE window not found"
        return 1
    fi
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

# Save current document using Ctrl+S
save_document() {
    local user=$1
    local display=$2

    echo "Saving document..."
    safe_xdotool $user $display key --delay 200 ctrl+s
    sleep 1
}

# Close ONLYOFFICE using Ctrl+Q
close_onlyoffice() {
    local user=$1
    local display=$2

    echo "Closing ONLYOFFICE..."
    if focus_onlyoffice_window; then
        safe_xdotool $user $display key --delay 200 ctrl+q
        sleep 2
    fi
}

# Clean up temporary files from previous tasks
cleanup_temp_files() {
    echo "Cleaning up temporary files..."
    rm -f /tmp/onlyoffice_*.log 2>/dev/null || true
    rm -f /tmp/create_*.py 2>/dev/null || true
    rm -f /tmp/*.docx.tmp 2>/dev/null || true
    rm -f /tmp/*.xlsx.tmp 2>/dev/null || true
    rm -f /tmp/*.pptx.tmp 2>/dev/null || true
}

# Export these functions for use in other scripts
export -f wait_for_window
export -f wait_for_file
export -f wait_for_process
export -f is_onlyoffice_running
export -f protect_onlyoffice_from_oom
export -f kill_onlyoffice
export -f focus_window
export -f get_onlyoffice_window_id
export -f focus_onlyoffice_window
export -f safe_xdotool
export -f save_document
export -f close_onlyoffice
export -f cleanup_temp_files
