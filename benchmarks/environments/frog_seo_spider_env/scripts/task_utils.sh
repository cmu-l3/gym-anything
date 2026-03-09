#!/bin/bash
# Shared utilities for Screaming Frog SEO Spider tasks
# NOTE: This environment uses REAL websites (https://crawler-test.com/)
#       NO local test servers are used

# Wait for a process to start
wait_for_process() {
    local process_name="$1"
    local timeout="${2:-30}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "$process_name" > /dev/null 2>&1; then
            echo "Process '$process_name' is running"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Timeout waiting for process '$process_name'"
    return 1
}

# Wait for a window to appear
wait_for_window() {
    local window_title="$1"
    local timeout="${2:-30}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_title"; then
            echo "Window '$window_title' found"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Timeout waiting for window '$window_title'"
    return 1
}

# Get Screaming Frog window ID
get_screamingfrog_window_id() {
    DISPLAY=:1 wmctrl -l | grep -i "screaming frog\|seo spider" | head -1 | awk '{print $1}'
}

# Focus a window by ID
focus_window() {
    local wid="$1"
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        sleep 0.5
    fi
}

# Check if Screaming Frog is running
is_screamingfrog_running() {
    pgrep -fi "screamingfrog" > /dev/null 2>&1
}

# Kill Screaming Frog processes
kill_screamingfrog() {
    local username="${1:-ga}"
    echo "Killing any existing Screaming Frog processes..."
    pkill -f "ScreamingFrogSEOSpider" 2>/dev/null || true
    pkill -f "screamingfrogseospider" 2>/dev/null || true
    sleep 1
}

# Safe xdotool command
safe_xdotool() {
    local user="$1"
    local display="$2"
    shift 2
    su - "$user" -c "DISPLAY=$display xdotool $*" 2>/dev/null || true
}

# Take a screenshot
take_screenshot() {
    local output_path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output_path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$output_path" 2>/dev/null || true
}

# Check if a crawl export file exists
check_export_exists() {
    local export_dir="${1:-/home/ga/Documents/SEO/exports}"
    local pattern="${2:-*.csv}"
    local timeout="${3:-10}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if ls "$export_dir"/$pattern 1> /dev/null 2>&1; then
            echo "Export file found in $export_dir"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# Get the latest export file
get_latest_export() {
    local export_dir="${1:-/home/ga/Documents/SEO/exports}"
    local pattern="${2:-*.csv}"
    ls -t "$export_dir"/$pattern 2>/dev/null | head -1
}

# Count URLs in a crawl export
count_urls_in_export() {
    local export_file="$1"
    if [ -f "$export_file" ]; then
        # Subtract 1 for the header row
        local count=$(wc -l < "$export_file")
        echo $((count - 1))
    else
        echo 0
    fi
}

# Check if crawl is complete by looking at window title
is_crawl_complete() {
    local window_title=$(DISPLAY=:1 wmctrl -l | grep -i "screaming frog\|seo spider" | head -1)
    # When crawling, title often shows "Crawling" or percentage
    # When complete, it usually shows the URL or "Crawl Complete"
    if echo "$window_title" | grep -qi "crawl"; then
        if echo "$window_title" | grep -qi "complete\|100%\|finished"; then
            return 0
        fi
        return 1
    fi
    return 0
}

# Wait for crawl to complete
wait_for_crawl_complete() {
    local timeout="${1:-120}"
    local elapsed=0

    echo "Waiting for crawl to complete..."
    while [ $elapsed -lt $timeout ]; do
        if is_crawl_complete; then
            echo "Crawl appears to be complete"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "Timeout waiting for crawl to complete"
    return 1
}

# Wait for Screaming Frog to be fully loaded and ready (not just process running)
# This performs actual UI verification to ensure the main interface is visible
wait_for_sf_ready() {
    local timeout="${1:-60}"
    local elapsed=0
    local min_wait=15  # Minimum time to wait even if checks pass (app needs time to stabilize)

    echo "Waiting for Screaming Frog to be fully ready..."
    while [ $elapsed -lt $timeout ]; do
        # First check if process is running
        if ! is_screamingfrog_running; then
            echo "  [${elapsed}s] Process not yet running..."
            sleep 2
            elapsed=$((elapsed + 2))
            continue
        fi

        # Check window exists
        local WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "screaming frog" | head -1)
        if [ -z "$WINDOW_TITLE" ]; then
            echo "  [${elapsed}s] Window not yet visible..."
            sleep 2
            elapsed=$((elapsed + 2))
            continue
        fi

        # Check that we're NOT on loading/splash screen
        # Loading screens typically show progress or "Loading" text
        if echo "$WINDOW_TITLE" | grep -qi "loading\|initializ\|starting\|splash"; then
            echo "  [${elapsed}s] Still on loading screen..."
            sleep 2
            elapsed=$((elapsed + 2))
            continue
        fi

        # ADDITIONAL UI VERIFICATION: Try to detect if main interface elements exist
        # Take a screenshot and check file size (splash screen is typically smaller/simpler)
        local test_screenshot="/tmp/sf_ready_check_$$.png"
        take_screenshot "$test_screenshot"

        if [ -f "$test_screenshot" ]; then
            local file_size=$(stat -c %s "$test_screenshot" 2>/dev/null || echo "0")
            rm -f "$test_screenshot"

            # Main interface screenshots are typically larger than splash screens
            # Splash screen: ~100-300KB, Main interface: ~500KB+
            if [ "$file_size" -lt 400000 ]; then
                echo "  [${elapsed}s] Screenshot too small (${file_size} bytes), likely still loading..."
                sleep 2
                elapsed=$((elapsed + 2))
                continue
            fi
        fi

        # Try to verify URL bar is accessible using xdotool
        # The main window should respond to focus
        local wid=$(get_screamingfrog_window_id)
        if [ -n "$wid" ]; then
            # Try to activate window - if this fails, UI may not be ready
            if ! DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null; then
                echo "  [${elapsed}s] Cannot activate window yet..."
                sleep 2
                elapsed=$((elapsed + 2))
                continue
            fi
        fi

        # Ensure minimum wait time for stability
        if [ $elapsed -ge $min_wait ]; then
            echo "Screaming Frog UI is ready (waited ${elapsed}s, screenshot size OK, window activatable)"
            # Take and save a "ready state" screenshot for verification
            take_screenshot /tmp/sf_ready_state.png
            return 0
        else
            echo "  [${elapsed}s] Checks passing, waiting for stability (min ${min_wait}s)..."
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "WARNING: Timeout waiting for Screaming Frog to be ready after ${timeout}s"
    # Take screenshot anyway to document state
    take_screenshot /tmp/sf_timeout_state.png
    return 1
}

# Ensure JSON file is created even on error
ensure_result_file() {
    local result_file="${1:-/tmp/task_result.json}"
    local error_msg="${2:-unknown error}"

    if [ ! -f "$result_file" ]; then
        echo "Creating fallback result file due to: $error_msg"
        cat > "$result_file" << EOF
{
    "error": true,
    "error_message": "$error_msg",
    "screaming_frog_running": false,
    "timestamp": "$(date -Iseconds)"
}
EOF
        chmod 666 "$result_file" 2>/dev/null || true
    fi
}

echo "Task utilities loaded"
echo "NOTE: This environment uses REAL websites - https://crawler-test.com/"
