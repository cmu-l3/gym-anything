#!/bin/bash
# Shared utilities for Moodle task setup and export scripts

# =============================================================================
# Auto-check: wait for Moodle web service on source
# This ensures web service is ready after cache restore
# =============================================================================
echo "Checking Moodle web service readiness..."
_moodle_ready=false
for _moodle_check_i in $(seq 1 60); do
    _moodle_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/" 2>/dev/null || echo "000")
    if [ "$_moodle_code" = "200" ] || [ "$_moodle_code" = "302" ] || [ "$_moodle_code" = "303" ]; then
        echo "Moodle web service is ready"
        _moodle_ready=true
        break
    fi
    # At 30s mark, try restarting Docker containers and Apache
    if [ "$_moodle_check_i" -eq 15 ]; then
        echo "Moodle not responding after 30s, restarting Docker containers and Apache..."
        docker compose -f /home/ga/moodle/docker-compose.yml restart 2>/dev/null \
            || docker-compose -f /home/ga/moodle/docker-compose.yml restart 2>/dev/null || true
        systemctl restart apache2 2>/dev/null || true
    fi
    sleep 2
done
if [ "$_moodle_ready" != "true" ]; then
    echo "WARNING: Moodle not ready after 120s, forcing restart..."
    docker compose -f /home/ga/moodle/docker-compose.yml restart 2>/dev/null \
        || docker-compose -f /home/ga/moodle/docker-compose.yml restart 2>/dev/null || true
    systemctl restart apache2 2>/dev/null || true
    sleep 10
fi

# =============================================================================
# Database Utilities
# =============================================================================

# Detect MariaDB method (Docker or native)
_get_mariadb_method() {
    cat /tmp/mariadb_method 2>/dev/null || echo "native"
}

# Execute SQL query against Moodle database (auto-detects Docker vs native)
# Args: $1 - SQL query
# Returns: query result (tab-separated, no column headers)
moodle_query() {
    local query="$1"
    local method=$(_get_mariadb_method)

    if [ "$method" = "docker" ]; then
        docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
    else
        mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
    fi
}

# Execute SQL query with column headers
moodle_query_headers() {
    local query="$1"
    local method=$(_get_mariadb_method)

    if [ "$method" = "docker" ]; then
        docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
    else
        mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
    fi
}

# Get total course count (excluding site course id=1)
get_course_count() {
    moodle_query "SELECT COUNT(*) FROM mdl_course WHERE id > 1"
}

# Get total user count (excluding admin and guest)
get_user_count() {
    moodle_query "SELECT COUNT(*) FROM mdl_user WHERE deleted = 0 AND id > 2"
}

# Check if course exists by short name
# Args: $1 - short name
# Returns: 0 if found, 1 if not found
course_exists() {
    local shortname="$1"
    local count=$(moodle_query "SELECT COUNT(*) FROM mdl_course WHERE LOWER(TRIM(shortname))=LOWER(TRIM('$shortname'))")
    [ "$count" -gt 0 ]
}

# Get course by short name
# Args: $1 - short name
# Returns: tab-separated: id, fullname, shortname, category
get_course_by_shortname() {
    local shortname="$1"
    moodle_query "SELECT id, fullname, shortname, category FROM mdl_course WHERE LOWER(TRIM(shortname))=LOWER(TRIM('$shortname')) LIMIT 1"
}

# Get course by full name (case-insensitive)
# Args: $1 - full name
# Returns: tab-separated: id, fullname, shortname, category
get_course_by_fullname() {
    local fullname="$1"
    moodle_query "SELECT id, fullname, shortname, category FROM mdl_course WHERE LOWER(TRIM(fullname))=LOWER(TRIM('$fullname')) LIMIT 1"
}

# Get user by username
# Args: $1 - username
# Returns: tab-separated: id, username, firstname, lastname, email
get_user_by_username() {
    local username="$1"
    moodle_query "SELECT id, username, firstname, lastname, email FROM mdl_user WHERE LOWER(TRIM(username))=LOWER(TRIM('$username')) AND deleted=0 LIMIT 1"
}

# Check enrollment status
# Args: $1 - user_id, $2 - course_id
# Returns: 0 if enrolled, 1 if not
is_user_enrolled() {
    local user_id="$1"
    local course_id="$2"
    local count=$(moodle_query "SELECT COUNT(*) FROM mdl_user_enrolments ue JOIN mdl_enrol e ON ue.enrolid=e.id WHERE ue.userid=$user_id AND e.courseid=$course_id AND ue.status=0")
    [ "$count" -gt 0 ]
}

# Get enrollment count for a course
# Args: $1 - course_id
get_enrollment_count() {
    local course_id="$1"
    moodle_query "SELECT COUNT(*) FROM mdl_user_enrolments ue JOIN mdl_enrol e ON ue.enrolid=e.id WHERE e.courseid=$course_id AND ue.status=0"
}

# Get assignment by name in a course
# Args: $1 - assignment name, $2 - course_id
get_assignment_by_name() {
    local name="$1"
    local course_id="$2"
    moodle_query "SELECT a.id, a.name, a.course, a.duedate, a.allowsubmissionsfromdate FROM mdl_assign a WHERE LOWER(TRIM(a.name))=LOWER(TRIM('$name')) AND a.course=$course_id LIMIT 1"
}

# Get category by name
# Args: $1 - category name
get_category_by_name() {
    local name="$1"
    moodle_query "SELECT id, name, idnumber FROM mdl_course_categories WHERE LOWER(TRIM(name))=LOWER(TRIM('$name')) LIMIT 1"
}

# =============================================================================
# Web Service Wait
# =============================================================================

# Wait for Moodle web service to be ready
wait_for_moodle() {
    local timeout=${1:-120}
    local elapsed=0
    local restarted=false
    echo "Waiting for Moodle web service..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
            echo "Moodle is ready (HTTP $HTTP_CODE) after ${elapsed}s"
            return 0
        fi
        # At halfway point, try restarting services
        if [ "$restarted" = "false" ] && [ $elapsed -ge 30 ]; then
            echo "Moodle not responding after ${elapsed}s, restarting services..."
            docker compose -f /home/ga/moodle/docker-compose.yml restart 2>/dev/null \
                || docker-compose -f /home/ga/moodle/docker-compose.yml restart 2>/dev/null || true
            systemctl restart apache2 2>/dev/null || true
            restarted=true
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Moodle not ready after ${timeout}s"
    return 1
}

# Launch Firefox with web service wait
restart_firefox() {
    local url="${1:-http://localhost/}"

    # Wait for Moodle web service before launching Firefox
    wait_for_moodle 120 || echo "WARNING: Moodle may not be ready"

    # Kill any stale Firefox
    pkill -9 -f firefox 2>/dev/null || true
    sleep 3

    su - ga -c "DISPLAY=:1 firefox '$url' > /tmp/firefox_moodle.log 2>&1 &"

    # Wait for Firefox window
    local ff_started=false
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|moodle"; then
            ff_started=true
            echo "Firefox window detected after ${i}s"
            break
        fi
        sleep 1
    done

    if [ "$ff_started" = true ]; then
        sleep 2
        # Maximize Firefox window
        local wid
        wid=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
        if [ -n "$wid" ]; then
            DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
            DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        fi
    fi
}

# =============================================================================
# Window Management Utilities
# =============================================================================

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
        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: Window not found after ${timeout}s"
    return 1
}

# Wait for a file to be created or modified
# Args: $1 - file path
#       $2 - timeout in seconds (default: 10)
wait_for_file() {
    local filepath="$1"
    local timeout=${2:-10}
    local start=$(date +%s)

    echo "Waiting for file: $filepath"

    while [ $(($(date +%s) - start)) -lt $timeout ]; do
        if [ -f "$filepath" ]; then
            echo "File ready: $filepath"
            return 0
        fi
        sleep 0.5
    done

    echo "Timeout: File not found: $filepath"
    return 1
}

# Focus a window
# Args: $1 - window ID
focus_window() {
    local window_id="$1"

    if DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null || DISPLAY=:1 wmctrl -a "$window_id" 2>/dev/null; then
        sleep 0.3
        echo "Window focused: $window_id"
        return 0
    fi

    echo "Failed to focus window: $window_id"
    return 1
}

# Get the window ID for Firefox
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'
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

# =============================================================================
# JSON Export Utilities
# =============================================================================

# Safely write a JSON result file
# Args: $1 - temp file content (already written), $2 - final destination path
safe_write_json() {
    local temp_file="$1"
    local dest_path="$2"

    # Remove old file
    rm -f "$dest_path" 2>/dev/null || sudo rm -f "$dest_path" 2>/dev/null || true

    # Copy temp to final
    cp "$temp_file" "$dest_path" 2>/dev/null || sudo cp "$temp_file" "$dest_path"

    # Set permissions
    chmod 666 "$dest_path" 2>/dev/null || sudo chmod 666 "$dest_path" 2>/dev/null || true

    # Cleanup temp
    rm -f "$temp_file"

    echo "Result saved to $dest_path"
}

# =============================================================================
# Export functions for use in sourced scripts
# =============================================================================
export -f _get_mariadb_method
export -f moodle_query
export -f moodle_query_headers
export -f get_course_count
export -f get_user_count
export -f course_exists
export -f get_course_by_shortname
export -f get_course_by_fullname
export -f get_user_by_username
export -f is_user_enrolled
export -f get_enrollment_count
export -f get_assignment_by_name
export -f get_category_by_name
export -f wait_for_moodle
export -f restart_firefox
export -f wait_for_window
export -f wait_for_file
export -f focus_window
export -f get_firefox_window_id
export -f take_screenshot
export -f safe_write_json
