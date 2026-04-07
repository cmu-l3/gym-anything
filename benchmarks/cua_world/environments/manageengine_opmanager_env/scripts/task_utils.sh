#!/bin/bash
# Shared utilities for all ManageEngine OpManager tasks
# Provides database queries, API calls, window management, and JSON export functions

# ============================================================
# OpManager Configuration
# ============================================================
OPMANAGER_DIR=$(cat /tmp/opmanager_install_dir 2>/dev/null || echo "/opt/ManageEngine/OpManager")
OPMANAGER_URL="http://localhost:8060"
OPMANAGER_USER="admin"
OPMANAGER_PASS="Admin@123"

# ============================================================
# Database Utilities
# ============================================================

# Execute a SQL query against OpManager's bundled PostgreSQL
opmanager_query() {
    local query="$1"
    local PG_BIN=$(cat /tmp/opmanager_pg_bin 2>/dev/null)
    local PG_PORT=$(cat /tmp/opmanager_pg_port 2>/dev/null || echo "13306")
    if [ -n "$PG_BIN" ] && [ -f "$PG_BIN" ]; then
        cd /tmp
        sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -t -A -c "$query" 2>/dev/null
    fi
}

# Execute query with column headers
opmanager_query_headers() {
    local query="$1"
    local PG_BIN=$(cat /tmp/opmanager_pg_bin 2>/dev/null)
    local PG_PORT=$(cat /tmp/opmanager_pg_port 2>/dev/null || echo "13306")
    if [ -n "$PG_BIN" ] && [ -f "$PG_BIN" ]; then
        cd /tmp
        sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c "$query" 2>/dev/null
    fi
}

# ============================================================
# API Utilities
# ============================================================

# Get a session cookie for OpManager API calls
opmanager_login() {
    curl -s -c /tmp/opmanager_task_cookies.txt \
        -d "userName=${OPMANAGER_USER}&password=${OPMANAGER_PASS}&domainName=local" \
        "${OPMANAGER_URL}/apiclient/ember/Login.jsp" > /dev/null 2>&1
}

# Make an API call with session auth
opmanager_api_get() {
    local endpoint="$1"
    local api_key=$(cat /tmp/opmanager_api_key 2>/dev/null)

    if [ -n "$api_key" ]; then
        curl -s "${OPMANAGER_URL}${endpoint}?apiKey=${api_key}" 2>/dev/null
    else
        # Fall back to session-based auth
        opmanager_login
        curl -s -b /tmp/opmanager_task_cookies.txt "${OPMANAGER_URL}${endpoint}" 2>/dev/null
    fi
}

opmanager_api_post() {
    local endpoint="$1"
    local data="$2"
    local api_key=$(cat /tmp/opmanager_api_key 2>/dev/null)

    if [ -n "$api_key" ]; then
        curl -s -X POST \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "${data}&apiKey=${api_key}" \
            "${OPMANAGER_URL}${endpoint}" 2>/dev/null
    else
        opmanager_login
        curl -s -X POST \
            -b /tmp/opmanager_task_cookies.txt \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "$data" \
            "${OPMANAGER_URL}${endpoint}" 2>/dev/null
    fi
}

# ============================================================
# Service Health Utilities
# ============================================================

# Check if OpManager is running and accessible
check_opmanager_health() {
    local HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$OPMANAGER_URL" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
        return 0
    fi
    return 1
}

# Wait for OpManager to be ready
wait_for_opmanager_ready() {
    local timeout=${1:-120}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if check_opmanager_health; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

# ============================================================
# Window Management Utilities
# ============================================================

# Wait for a window matching pattern to appear
wait_for_window() {
    local pattern="$1"
    local timeout=${2:-30}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# Wait for file to be created
wait_for_file() {
    local filepath="$1"
    local timeout=${2:-30}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if [ -f "$filepath" ]; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# Focus a specific window by ID
focus_window() {
    local wid="$1"
    DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
    sleep 0.5
}

# Get Firefox window ID
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}'
}

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 xwd -root -silent | convert xwd:- "$path" 2>/dev/null || true
}

# ============================================================
# OpManager Service Recovery Utilities
# ============================================================

# Detect OpManager service state via HTTP
# Returns: "running", "maintenance", "down"
detect_opmanager_service_state() {
    local body_file="/tmp/om_state_check_$$.html"
    local HTTP_CODE
    HTTP_CODE=$(curl -s -o "$body_file" -w "%{http_code}" \
        --max-time 10 "$OPMANAGER_URL" 2>/dev/null)

    if [ "$HTTP_CODE" = "000" ] || [ -z "$HTTP_CODE" ]; then
        rm -f "$body_file"
        echo "down"
        return
    fi

    if grep -qi "Service has not started\|Problem in starting\|maintenance" "$body_file" 2>/dev/null; then
        rm -f "$body_file"
        echo "maintenance"
        return
    fi

    rm -f "$body_file"
    echo "running"
}

# Ensure OpManager service is running (restart if in maintenance/down)
ensure_opmanager_service() {
    local max_retries=${1:-2}
    local try=0

    while [ $try -lt $max_retries ]; do
        try=$((try + 1))
        local state
        state=$(detect_opmanager_service_state)

        if [ "$state" = "running" ]; then
            echo "OpManager service is healthy"
            return 0
        fi

        echo "OpManager is $state (attempt $try/$max_retries), restarting..."
        local OM_DIR
        OM_DIR=$(cat /tmp/opmanager_install_dir 2>/dev/null || echo "/opt/ManageEngine/OpManager")

        "$OM_DIR/bin/shutdown.sh" 2>/dev/null || true
        sleep 10
        pkill -f "$OM_DIR/jre/bin/java" 2>/dev/null || true
        sleep 5

        systemctl start OpManager.service 2>/dev/null || {
            cd "$OM_DIR/bin" && nohup ./run.sh > /tmp/opmanager_restart.log 2>&1 &
        }

        wait_for_opmanager_ready 300
        sleep 15
    done

    [ "$(detect_opmanager_service_state)" = "running" ]
}

# Fix password-change-on-login flags in the database
_fix_password_db_flags() {
    local PG_BIN PG_PORT
    PG_BIN=$(cat /tmp/opmanager_pg_bin 2>/dev/null)
    PG_PORT=$(cat /tmp/opmanager_pg_port 2>/dev/null || echo "13306")

    if [ -n "$PG_BIN" ] && [ -f "$PG_BIN" ]; then
        cd /tmp
        sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c \
            "UPDATE aaapasswordstatus SET change_pwd_on_login = false WHERE password_id = 1;" 2>/dev/null || true
        sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c \
            "UPDATE aaauserproperty SET prop_value = 'CHANGED_ON_FIRST_LOGIN' WHERE user_id = 1 AND prop_name = 'PASSWORD_CURRENT_STATUS';" 2>/dev/null || true
        sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c \
            "INSERT INTO aaauserproperty (user_id, prop_name, prop_value) SELECT 1, 'PASSWORD_CURRENT_STATUS', 'CHANGED_ON_FIRST_LOGIN' WHERE NOT EXISTS (SELECT 1 FROM aaauserproperty WHERE user_id = 1 AND prop_name = 'PASSWORD_CURRENT_STATUS');" 2>/dev/null || true
        sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c \
            "UPDATE aaapasswordrule SET login_change_pwd = false WHERE password_rule_id IS NOT NULL;" 2>/dev/null || true
        sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c \
            "UPDATE aaapassword SET modified_time = EXTRACT(EPOCH FROM NOW()) * 1000 WHERE password_id = 1;" 2>/dev/null || true
        echo "  DB password flags updated"
    fi
}

# Verify login works with expected password; fix DB flags if change-password still appears
ensure_correct_password() {
    echo "Verifying password state via curl..."
    local resp
    resp=$(curl -s -c /tmp/om_pwcheck.txt -L --max-time 15 \
        -d "userName=${OPMANAGER_USER}&password=${OPMANAGER_PASS}&domainName=local" \
        -o /tmp/om_pwcheck_body.html -w "%{http_code}" \
        "${OPMANAGER_URL}/apiclient/ember/Login.jsp" 2>/dev/null)

    if grep -qi "ChangePassword\|changepassword\|change_password" /tmp/om_pwcheck_body.html 2>/dev/null; then
        echo "  Change-password redirect detected, applying DB fix..."
        _fix_password_db_flags
        return 1
    fi

    if [ "$resp" = "200" ] || [ "$resp" = "302" ] || [ "$resp" = "303" ]; then
        echo "  Login with ${OPMANAGER_PASS} works"
        return 0
    fi

    # Try default password
    resp=$(curl -s -c /tmp/om_pwcheck2.txt -L --max-time 15 \
        -d "userName=${OPMANAGER_USER}&password=admin&domainName=local" \
        -o /tmp/om_pwcheck2_body.html -w "%{http_code}" \
        "${OPMANAGER_URL}/apiclient/ember/Login.jsp" 2>/dev/null)

    if [ "$resp" = "200" ] || [ "$resp" = "302" ] || [ "$resp" = "303" ]; then
        echo "  Default password still active, applying DB fix..."
        _fix_password_db_flags
        return 1
    fi

    echo "  Could not verify password state (HTTP $resp)"
    return 1
}

# ============================================================
# Browser State Detection & Recovery Utilities
# ============================================================

# Handle Change Password page in browser via xdotool
handle_browser_change_password() {
    echo "  Handling Change Password page in browser..."

    # Apply DB fix first so it doesn't recur
    _fix_password_db_flags

    # Dismiss QR popup overlay (appears on top of password form)
    DISPLAY=:1 xdotool key Escape
    sleep 2
    DISPLAY=:1 xdotool mousemove 1326 372 click 1
    sleep 2

    # New password field
    DISPLAY=:1 xdotool mousemove 668 360 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --delay 30 "$OPMANAGER_PASS"
    sleep 0.5

    # Confirm password field
    DISPLAY=:1 xdotool mousemove 668 431 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --delay 30 "$OPMANAGER_PASS"
    sleep 0.5

    # Email field
    DISPLAY=:1 xdotool mousemove 668 506 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --delay 30 "admin@opmanager-lab.local"
    sleep 0.5

    # Click Update Password
    DISPLAY=:1 xdotool mousemove 758 615 click 1
    sleep 10

    # Dismiss setup wizard
    DISPLAY=:1 xdotool key Escape
    sleep 1
    DISPLAY=:1 xdotool mousemove 1467 362 click 1
    sleep 2
}

# Handle login page in browser via xdotool
handle_browser_login() {
    echo "  Handling login page in browser..."

    # Tab-based login: click username, clear, type, tab to password, type, enter
    # This is more robust than coordinate-based clicking on specific fields
    DISPLAY=:1 xdotool mousemove 960 400 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --delay 30 "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --delay 30 "$OPMANAGER_PASS"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 12

    # Dismiss any popups (QR code, setup wizard)
    DISPLAY=:1 xdotool key Escape
    sleep 2
    DISPLAY=:1 xdotool key Escape
    sleep 1
}

# Ensure Firefox is running and showing OpManager dashboard
# This is called from setup_task.sh as the last safety net before the agent starts.
# Handles all failure modes: no Firefox, service down, maintenance page,
# login page, change password page.
ensure_firefox_on_opmanager() {
    local max_attempts=${1:-3}
    local attempt=0

    # Step 0: Ensure OpManager service is healthy (handles maintenance/down)
    ensure_opmanager_service 2

    # Step 0b: Verify password state and fix DB flags if needed
    ensure_correct_password

    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        echo "Ensure Firefox on OpManager (attempt $attempt/$max_attempts)..."

        # Step 1: Ensure Firefox is running
        if ! pgrep -f firefox > /dev/null 2>&1; then
            echo "  Firefox not running, starting..."
            find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true
            find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true
            su - ga -c "export DISPLAY=:1; nohup firefox '${OPMANAGER_URL}/' > /tmp/firefox_task_recovery.log 2>&1 &"
            sleep 15
        fi

        # Step 2: Wait for Firefox window
        local found=false
        for i in $(seq 1 45); do
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
                found=true
                break
            fi
            if [ $i -eq 20 ] && ! pgrep -f firefox > /dev/null 2>&1; then
                echo "  Firefox process died at ${i}s, restarting..."
                find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true
                find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true
                su - ga -c "export DISPLAY=:1; nohup firefox '${OPMANAGER_URL}/' > /tmp/firefox_task_recovery2.log 2>&1 &"
            fi
            sleep 1
        done

        if [ "$found" = false ]; then
            echo "  Firefox window not found, retrying..."
            pkill -f firefox 2>/dev/null || true
            sleep 3
            continue
        fi

        # Step 3: Focus and maximize Firefox
        local wid
        wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
        if [ -n "$wid" ]; then
            DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
            DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        fi
        sleep 1

        # Step 4: Navigate to OpManager URL
        DISPLAY=:1 xdotool key ctrl+l
        sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers "http://localhost:8060/"
        DISPLAY=:1 xdotool key Return
        sleep 10

        # Step 5: Detect browser state from window title and handle
        local title
        title=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
        echo "  Window title: $title"

        if echo "$title" | grep -qi "change.password\|update.password"; then
            handle_browser_change_password
        elif echo "$title" | grep -qi "maintenance\|service.*not.*started"; then
            echo "  Maintenance page in browser, restarting service..."
            ensure_opmanager_service 1
            DISPLAY=:1 xdotool key F5
            sleep 15
            continue
        elif echo "$title" | grep -qi "login\|sign.in"; then
            handle_browser_login
            # Re-check: login may lead to Change Password page
            sleep 3
            local title2
            title2=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
            echo "  Post-login title: $title2"
            if echo "$title2" | grep -qi "change.password\|update.password"; then
                handle_browser_change_password
            fi
        fi

        # Step 6: Dismiss any remaining popups
        DISPLAY=:1 xdotool key Escape
        sleep 1
        DISPLAY=:1 xdotool key Escape
        sleep 1

        # Step 7: Final navigation to ensure we're on the dashboard
        DISPLAY=:1 xdotool key ctrl+l
        sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers "http://localhost:8060/"
        DISPLAY=:1 xdotool key Return
        sleep 8

        # Step 8: Final state check - handle Change Password if it persists
        local title_final
        title_final=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
        if echo "$title_final" | grep -qi "change.password\|update.password"; then
            echo "  Change Password still showing after navigation, handling..."
            handle_browser_change_password
            # Navigate to dashboard one more time
            DISPLAY=:1 xdotool key ctrl+l
            sleep 0.5
            DISPLAY=:1 xdotool type --clearmodifiers "http://localhost:8060/"
            DISPLAY=:1 xdotool key Return
            sleep 8
        fi
        DISPLAY=:1 xdotool key Escape
        sleep 1

        echo "  Firefox is on OpManager"
        return 0
    done

    echo "WARNING: Could not ensure Firefox on OpManager after $max_attempts attempts"
    return 1
}

# ============================================================
# JSON Export Utilities
# ============================================================

# Safely write JSON result file with proper permissions
safe_write_json() {
    local temp_file="$1"
    local dest_file="$2"

    # Remove old file with fallbacks
    rm -f "$dest_file" 2>/dev/null || sudo rm -f "$dest_file" 2>/dev/null || true

    # Copy new file with fallbacks
    cp "$temp_file" "$dest_file" 2>/dev/null || sudo cp "$temp_file" "$dest_file"

    # Set permissions so anyone can read
    chmod 666 "$dest_file" 2>/dev/null || sudo chmod 666 "$dest_file" 2>/dev/null || true

    # Cleanup temp
    rm -f "$temp_file" 2>/dev/null || true
}
