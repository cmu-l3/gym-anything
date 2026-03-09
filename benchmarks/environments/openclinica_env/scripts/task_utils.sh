#!/bin/bash
# Shared utility functions for OpenClinica tasks

# OpenClinica URL
OC_URL="http://localhost:8080/OpenClinica"

# Debug log
VERIFIER_DEBUG_LOG="/tmp/verifier_debug.log"

# ============================================================
# Database query function
# ============================================================
oc_query() {
    local query="$1"
    local result
    local exit_code

    result=$(docker exec oc-postgres psql -U clinica openclinica -t -A -c "$query" 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "DB_ERROR: Query failed with exit code $exit_code" >> "$VERIFIER_DEBUG_LOG"
        echo "DB_ERROR: Query: $query" >> "$VERIFIER_DEBUG_LOG"
        echo "DB_ERROR: Output: $result" >> "$VERIFIER_DEBUG_LOG"
        echo ""
        return 1
    fi

    # Check for error messages in output
    if echo "$result" | grep -qi "ERROR"; then
        echo "DB_ERROR: PostgreSQL error in result" >> "$VERIFIER_DEBUG_LOG"
        echo "DB_ERROR: Query: $query" >> "$VERIFIER_DEBUG_LOG"
        echo "DB_ERROR: Output: $result" >> "$VERIFIER_DEBUG_LOG"
        echo ""
        return 1
    fi

    echo "$result"
    return 0
}

# ============================================================
# Screenshot function
# ============================================================
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
    echo "Warning: Could not take screenshot"

    if [ -f "$output_file" ]; then
        echo "Screenshot saved: $output_file"
    fi
}

# ============================================================
# Window management functions
# ============================================================
wait_for_window() {
    local window_pattern="$1"
    local timeout=${2:-30}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}'
}

focus_firefox() {
    local wid=$(get_firefox_window_id)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 0.5
        return 0
    fi
    return 1
}

# ============================================================
# Login verification and recovery
# ============================================================
verify_openclinica_ready() {
    # Check if OpenClinica is responding
    local timeout=${1:-30}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/OpenClinica/" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

ensure_logged_in() {
    # Ensure Firefox is showing a logged-in OpenClinica page, not a 404 or login page
    # This function:
    # 1. Verifies OpenClinica is responding
    # 2. Navigates Firefox to the login page if needed
    # 3. Performs automated login via xdotool if login page is detected

    echo "Verifying OpenClinica is accessible..."
    if ! verify_openclinica_ready 60; then
        echo "ERROR: OpenClinica is not responding. Attempting Docker restart..."
        docker restart oc-app 2>/dev/null || true
        sleep 20
        if ! verify_openclinica_ready 120; then
            echo "FATAL: OpenClinica still not responding after restart"
            return 1
        fi
    fi

    # Navigate Firefox to main page
    focus_firefox
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool type --delay 20 'http://localhost:8080/OpenClinica/MainMenu' 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5

    # Check window title to see if we're logged in or on login page
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 || echo "")
    echo "Window title after navigation: $WINDOW_TITLE"

    # If we see "login" or error indicators, try to log in
    if echo "$WINDOW_TITLE" | grep -qi "login\|log in\|sign in\|404\|error\|problem"; then
        echo "Login page or error detected. Performing automated login..."

        # Wait for page to load
        sleep 3

        # Type username
        DISPLAY=:1 xdotool key Tab 2>/dev/null || true
        sleep 0.2
        DISPLAY=:1 xdotool type --delay 30 'root' 2>/dev/null || true
        sleep 0.2

        # Tab to password field
        DISPLAY=:1 xdotool key Tab 2>/dev/null || true
        sleep 0.2
        DISPLAY=:1 xdotool type --delay 30 'Admin123!' 2>/dev/null || true
        sleep 0.2

        # Press Enter to submit
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 5

        # Check if we're now logged in
        WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 || echo "")
        echo "Window title after login attempt: $WINDOW_TITLE"

        # Handle potential password reset page
        if echo "$WINDOW_TITLE" | grep -qi "reset\|change\|password"; then
            echo "Password reset page detected. Re-applying DB password fix..."

            # Re-apply the password timestamp fix via DB
            docker exec oc-postgres psql -U clinica openclinica -c "
                UPDATE user_account SET
                    passwd_timestamp = CURRENT_DATE + INTERVAL '365 days',
                    account_non_locked = true
                WHERE user_name = 'root';
            " 2>/dev/null || true

            # Restart Tomcat to clear cached session state
            docker restart oc-app 2>/dev/null || true
            echo "Restarted OpenClinica to clear cached password reset state..."
            sleep 15

            # Wait for OpenClinica to come back
            verify_openclinica_ready 120

            # Navigate to MainMenu
            focus_firefox
            sleep 0.5
            DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
            sleep 0.3
            DISPLAY=:1 xdotool type --delay 20 'http://localhost:8080/OpenClinica/MainMenu' 2>/dev/null || true
            DISPLAY=:1 xdotool key Return 2>/dev/null || true
            sleep 5

            # May need to re-login after restart
            WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 || echo "")
            if echo "$WINDOW_TITLE" | grep -qi "login\|log in\|sign in"; then
                echo "Re-logging in after restart..."
                sleep 2
                DISPLAY=:1 xdotool key Tab 2>/dev/null || true
                sleep 0.2
                DISPLAY=:1 xdotool type --delay 30 'root' 2>/dev/null || true
                sleep 0.2
                DISPLAY=:1 xdotool key Tab 2>/dev/null || true
                sleep 0.2
                DISPLAY=:1 xdotool type --delay 30 'Admin123!' 2>/dev/null || true
                sleep 0.2
                DISPLAY=:1 xdotool key Return 2>/dev/null || true
                sleep 5
            fi
        fi
    fi

    # Final verification - check we're on OpenClinica
    FINAL_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 || echo "")
    if echo "$FINAL_TITLE" | grep -qi "openclinica\|clinical\|welcome"; then
        echo "Successfully verified: logged into OpenClinica"
        return 0
    else
        echo "WARNING: Could not confirm OpenClinica login. Window: $FINAL_TITLE"
        # Try one more refresh
        DISPLAY=:1 xdotool key F5 2>/dev/null || true
        sleep 5
        return 0
    fi
}

# ============================================================
# Study context switching — navigates the browser to the correct study
# ============================================================
switch_active_study() {
    # Switch the active study in both the database AND the browser session.
    # Just updating study_user_role in the DB is NOT enough — the web session
    # has its own state that doesn't change on page refresh.
    local study_identifier="$1"

    # 1. Get study_id from DB
    local study_id
    study_id=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = '$study_identifier' LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$study_id" ]; then
        echo "WARNING: Study '$study_identifier' not found in database"
        return 1
    fi

    # 2. Update DB-level preferred study for root user
    oc_query "UPDATE study_user_role SET study_id = $study_id WHERE user_name = 'root'" 2>/dev/null || true
    echo "Set DB study context to $study_identifier (study_id=$study_id)"

    # 3. Switch in the browser via ChangeStudy servlet
    focus_firefox
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool type --delay 20 "http://localhost:8080/OpenClinica/ChangeStudy?id=${study_id}&action=confirm" 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 4

    # 4. After switching, navigate to MainMenu to confirm
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool type --delay 20 'http://localhost:8080/OpenClinica/MainMenu' 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 3

    echo "Switched active study to '$study_identifier' in browser"
    return 0
}

# ============================================================
# JSON utility functions
# ============================================================
json_escape() {
    local str="$1"
    echo "$str" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\n' | tr -d '\r'
}

safe_write_result() {
    local temp_file="$1"
    local dest="${2:-/tmp/task_result.json}"

    # Remove old file with fallback
    rm -f "$dest" 2>/dev/null || sudo rm -f "$dest" 2>/dev/null || true
    cp "$temp_file" "$dest" 2>/dev/null || sudo cp "$temp_file" "$dest"
    # Use 644 (owner read-write, others read-only) — NOT 666 — to prevent
    # adversarial agents from overwriting the result file
    chmod 644 "$dest" 2>/dev/null || sudo chmod 644 "$dest" 2>/dev/null || true
    rm -f "$temp_file"

    echo "Result saved to $dest"
    cat "$dest"
}

# ============================================================
# Result integrity nonce — prevents result file tampering
# ============================================================
generate_result_nonce() {
    # Generate a random nonce during setup that will be embedded in the result JSON.
    # The verifier reads the nonce from a setup-time file and checks it matches.
    local nonce
    nonce=$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)
    echo "$nonce" > /tmp/result_nonce
    chmod 600 /tmp/result_nonce 2>/dev/null || true
    echo "$nonce"
}

get_result_nonce() {
    cat /tmp/result_nonce 2>/dev/null || echo ""
}

# ============================================================
# Study-specific query helpers
# ============================================================
get_study_count() {
    oc_query "SELECT COUNT(*) FROM study WHERE parent_study_id IS NULL" 2>/dev/null || echo "0"
}

get_subject_count() {
    oc_query "SELECT COUNT(*) FROM study_subject" 2>/dev/null || echo "0"
}

get_user_count() {
    oc_query "SELECT COUNT(*) FROM user_account" 2>/dev/null || echo "0"
}

get_event_def_count() {
    oc_query "SELECT COUNT(*) FROM study_event_definition" 2>/dev/null || echo "0"
}

get_crf_count() {
    oc_query "SELECT COUNT(*) FROM crf" 2>/dev/null || echo "0"
}

# ============================================================
# Audit log check - verifies GUI interaction occurred
# ============================================================
get_recent_audit_count() {
    # Count recent audit_log_event entries (created during task execution).
    # OpenClinica logs GUI actions to this table; direct SQL INSERTs bypass it.
    # We count entries created in the last N minutes (default: task window of 15 min).
    local since="${1:-15}"
    oc_query "SELECT COUNT(*) FROM audit_log_event WHERE audit_date >= NOW() - INTERVAL '${since} minutes'" 2>/dev/null || echo "0"
}

get_audit_entity_types() {
    # Get distinct audit_table values from recent audit log entries — used to verify
    # the correct entity type was created via GUI. For example, creating a study should
    # generate audit entries referencing the 'study' table.
    # Returns comma-separated list of distinct audit_table values.
    local since="${1:-15}"
    oc_query "SELECT DISTINCT audit_table FROM audit_log_event WHERE audit_date >= NOW() - INTERVAL '${since} minutes' ORDER BY audit_table" 2>/dev/null | tr '\n' ',' | sed 's/,$//'
}

get_audit_for_entity() {
    # Count audit entries for a specific entity type since baseline.
    # $1 = audit_table filter (e.g. 'study', 'study_subject', 'user_account')
    # $2 = minutes window (default 15)
    local entity_table="$1"
    local since="${2:-15}"
    oc_query "SELECT COUNT(*) FROM audit_log_event WHERE audit_table = '$entity_table' AND audit_date >= NOW() - INTERVAL '${since} minutes'" 2>/dev/null || echo "0"
}

# Export functions for subshells
export -f oc_query
export -f take_screenshot
export -f wait_for_window
export -f get_firefox_window_id
export -f focus_firefox
export -f verify_openclinica_ready
export -f ensure_logged_in
export -f json_escape
export -f safe_write_result
export -f generate_result_nonce
export -f get_result_nonce
export -f get_study_count
export -f get_subject_count
export -f get_user_count
export -f get_event_def_count
export -f get_crf_count
export -f get_recent_audit_count
export -f get_audit_entity_types
export -f get_audit_for_entity
export -f switch_active_study
