#!/bin/bash
# Shared utilities for Manager.io task setup scripts.
# Source this file with: source /workspace/scripts/task_utils.sh

MANAGER_URL="http://localhost:8080"
FIREFOX_PROFILE="/home/ga/.mozilla/firefox/manager.profile"

# ---------------------------------------------------------------------------
# wait_for_manager: Poll until Manager.io HTTP endpoint responds
# ---------------------------------------------------------------------------
wait_for_manager() {
    local timeout=${1:-60}
    local elapsed=0

    echo "Waiting for Manager.io to be accessible..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -L "$MANAGER_URL/" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
            echo "Manager.io ready (HTTP $HTTP_CODE) after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "ERROR: Manager.io not accessible after ${timeout}s"
    return 1
}

# ---------------------------------------------------------------------------
# ensure_manager_running: Restart container if Manager.io is down
# ---------------------------------------------------------------------------
ensure_manager_running() {
    if ! curl -s -o /dev/null -w "%{http_code}" -L "$MANAGER_URL/" 2>/dev/null | grep -qE "200|302|303"; then
        echo "Manager.io not running. Restarting container..."
        cd /home/ga/manager && docker compose up -d 2>/dev/null || true
        wait_for_manager 60
    fi
}

# ---------------------------------------------------------------------------
# take_screenshot: Capture VNC desktop screenshot
# ---------------------------------------------------------------------------
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
        DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# get_firefox_window_id: Return the WM window ID of the Firefox window
# ---------------------------------------------------------------------------
get_firefox_window_id() {
    DISPLAY=:1 xdotool search --onlyvisible --name "Firefox" 2>/dev/null | tail -1
}

# ---------------------------------------------------------------------------
# wait_for_window: Wait until a window matching the given pattern appears
# ---------------------------------------------------------------------------
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# ---------------------------------------------------------------------------
# open_manager_at: Open Firefox at Manager.io and navigate to a module.
#
# Usage: open_manager_at <module> [action]
#   module : customers | sales_invoices | receipts | suppliers |
#             purchase_invoices | inventory | journal_entries |
#             credit_notes | debit_notes | reports | bank_accounts
#   action : new (optional — clicks the "New [Item]" button after arriving)
#
# This function:
#   1. Ensures Manager.io Docker container is running
#   2. Kills any existing Firefox
#   3. Starts Firefox at localhost:8080
#   4. Calls navigate_manager.py to login and navigate to the module
# ---------------------------------------------------------------------------
open_manager_at() {
    local module="${1:-}"
    local action="${2:-}"

    # Ensure Manager.io is accessible
    ensure_manager_running

    # Kill existing Firefox for a clean start
    pkill -f firefox 2>/dev/null || true
    sleep 3

    # Call the Python navigation helper
    if [ -n "$module" ]; then
        python3 /workspace/scripts/navigate_manager.py "$module" "$action"
    else
        # Just open at the login page
        su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid firefox \
            -profile '$FIREFOX_PROFILE' \
            --new-window '$MANAGER_URL/' \
            > /tmp/firefox_task.log 2>&1 &"
        sleep 10
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# record_task_start: Store initial state metadata for verification
#   $1 = state label (e.g., "customer_count", "invoice_count")
#   $2 = value or command to get value
# ---------------------------------------------------------------------------
record_task_start() {
    local label="$1"
    local value="$2"
    echo "$value" > "/tmp/manager_task_${label}"
    echo "Recorded initial ${label}: ${value}"
}
