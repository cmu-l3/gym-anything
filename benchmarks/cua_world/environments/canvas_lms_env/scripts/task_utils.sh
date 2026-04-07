#!/bin/bash
# Shared utilities for Canvas LMS task setup and export scripts

# =============================================================================
# Database Utilities
# =============================================================================

# Detect Canvas method (Docker)
_get_canvas_method() {
    cat /tmp/canvas_method 2>/dev/null || echo "docker"
}

# Execute SQL query against Canvas database (auto-detects Docker vs native)
# Args: $1 - SQL query
# Returns: query result (no column headers)
canvas_query() {
    local query="$1"
    local method=$(_get_canvas_method)

    if [ "$method" = "docker" ]; then
        # Fat container (lbjay/canvas-docker) uses canvas_development database
        docker exec canvas-lms psql -U canvas -d canvas_development -t -A -c "$query" 2>/dev/null
    else
        psql -U canvas -d canvas_development -t -A -c "$query" 2>/dev/null
    fi
}

# Execute SQL query with column headers
canvas_query_headers() {
    local query="$1"
    local method=$(_get_canvas_method)

    if [ "$method" = "docker" ]; then
        # Fat container (lbjay/canvas-docker) uses canvas_development database
        docker exec canvas-lms psql -U canvas -d canvas_development -c "$query" 2>/dev/null
    else
        psql -U canvas -d canvas_development -c "$query" 2>/dev/null
    fi
}

# =============================================================================
# User Management Utilities
# =============================================================================

# Get total user count
get_user_count() {
    canvas_query "SELECT COUNT(*) FROM users WHERE workflow_state = 'registered'"
}

# Get user by login name
# Args: $1 - login name (unique_id)
# Returns: pipe-separated: id, name, sortable_name, email
get_user_by_login() {
    local login="$1"
    canvas_query "SELECT u.id, u.name, u.sortable_name, p.unique_id
                  FROM users u
                  JOIN pseudonyms p ON u.id = p.user_id
                  WHERE LOWER(TRIM(p.unique_id)) = LOWER(TRIM('$login'))
                  AND u.workflow_state = 'registered'
                  LIMIT 1"
}

# Check if user exists by login name
# Args: $1 - login name
# Returns: 0 if found, 1 if not found
user_exists() {
    local login="$1"
    local count=$(canvas_query "SELECT COUNT(*) FROM pseudonyms WHERE LOWER(TRIM(unique_id)) = LOWER(TRIM('$login'))")
    [ "$count" -gt 0 ]
}

# =============================================================================
# Course Management Utilities
# =============================================================================

# Get total course count
get_course_count() {
    canvas_query "SELECT COUNT(*) FROM courses WHERE workflow_state = 'available'"
}

# Check if course exists by code
# Args: $1 - course code
# Returns: 0 if found, 1 if not found
course_exists() {
    local code="$1"
    local count=$(canvas_query "SELECT COUNT(*) FROM courses WHERE LOWER(TRIM(course_code)) = LOWER(TRIM('$code'))")
    [ "$count" -gt 0 ]
}

# Get course by code
# Args: $1 - course code
# Returns: pipe-separated: id, name, course_code
get_course_by_code() {
    local code="$1"
    canvas_query "SELECT id, name, course_code FROM courses
                  WHERE LOWER(TRIM(course_code)) = LOWER(TRIM('$code'))
                  AND workflow_state = 'available'
                  LIMIT 1"
}

# Get course by name
# Args: $1 - course name
# Returns: pipe-separated: id, name, course_code
get_course_by_name() {
    local name="$1"
    canvas_query "SELECT id, name, course_code FROM courses
                  WHERE LOWER(TRIM(name)) = LOWER(TRIM('$name'))
                  AND workflow_state = 'available'
                  LIMIT 1"
}

# Get course by ID
# Args: $1 - course ID
get_course_by_id() {
    local course_id="$1"
    canvas_query "SELECT id, name, course_code FROM courses WHERE id = $course_id"
}

# =============================================================================
# Enrollment Utilities
# =============================================================================

# Check enrollment status
# Args: $1 - user_id, $2 - course_id
# Returns: 0 if enrolled, 1 if not
is_user_enrolled() {
    local user_id="$1"
    local course_id="$2"
    local count=$(canvas_query "SELECT COUNT(*) FROM enrollments
                                WHERE user_id = $user_id
                                AND course_id = $course_id
                                AND workflow_state = 'active'")
    [ "$count" -gt 0 ]
}

# Get enrollment count for a course
# Args: $1 - course_id
get_enrollment_count() {
    local course_id="$1"
    canvas_query "SELECT COUNT(*) FROM enrollments
                  WHERE course_id = $course_id
                  AND workflow_state = 'active'"
}

# =============================================================================
# Assignment Utilities
# =============================================================================

# Get assignment count for a course
# Args: $1 - course_id
get_assignment_count() {
    local course_id="$1"
    canvas_query "SELECT COUNT(*) FROM assignments
                  WHERE context_id = $course_id
                  AND context_type = 'Course'
                  AND workflow_state = 'published'"
}

# Get assignment by title in a course
# Args: $1 - assignment title, $2 - course_id
get_assignment_by_title() {
    local title="$1"
    local course_id="$2"
    canvas_query "SELECT id, title, points_possible, due_at
                  FROM assignments
                  WHERE LOWER(TRIM(title)) = LOWER(TRIM('$title'))
                  AND context_id = $course_id
                  AND context_type = 'Course'
                  LIMIT 1"
}

# =============================================================================
# Module Utilities
# =============================================================================

# Get module count for a course
# Args: $1 - course_id
get_module_count() {
    local course_id="$1"
    canvas_query "SELECT COUNT(*) FROM context_modules
                  WHERE context_id = $course_id
                  AND context_type = 'Course'
                  AND workflow_state = 'active'"
}

# Get module by name in a course
# Args: $1 - module name, $2 - course_id
get_module_by_name() {
    local name="$1"
    local course_id="$2"
    canvas_query "SELECT id, name, position
                  FROM context_modules
                  WHERE LOWER(TRIM(name)) = LOWER(TRIM('$name'))
                  AND context_id = $course_id
                  AND context_type = 'Course'
                  LIMIT 1"
}

# =============================================================================
# Announcement Utilities
# =============================================================================

# Get announcement count for a course
# Args: $1 - course_id
get_announcement_count() {
    local course_id="$1"
    canvas_query "SELECT COUNT(*) FROM discussion_topics
                  WHERE context_id = $course_id
                  AND context_type = 'Course'
                  AND type = 'Announcement'
                  AND workflow_state = 'active'"
}

# Get announcement by title
# Args: $1 - title, $2 - course_id
get_announcement_by_title() {
    local title="$1"
    local course_id="$2"
    canvas_query "SELECT id, title, message
                  FROM discussion_topics
                  WHERE LOWER(TRIM(title)) = LOWER(TRIM('$title'))
                  AND context_id = $course_id
                  AND context_type = 'Course'
                  AND type = 'Announcement'
                  LIMIT 1"
}

# =============================================================================
# Canvas Health Check Utilities
# =============================================================================

# Check if Canvas web interface is accessible
# Args: $1 - timeout in seconds (default: 180)
# Returns: 0 if Canvas is accessible, 1 if not
wait_for_canvas_ready() {
    local timeout=${1:-180}
    local elapsed=0
    local canvas_url="http://localhost:3000/"
    local backoff=2

    echo "Verifying Canvas LMS is accessible (timeout: ${timeout}s)..."

    while [ $elapsed -lt $timeout ]; do
        # Try to get the page content to verify it's actually Canvas, not just any HTTP response
        local response=$(curl -s -L --connect-timeout 10 --max-time 15 "$canvas_url" 2>/dev/null | head -c 5000)
        local HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -L --connect-timeout 10 "$canvas_url" 2>/dev/null)

        # Check for actual Canvas content (login form or canvas branding)
        if echo "$response" | grep -qi "canvas\|instructure\|Log In\|email.*password" 2>/dev/null; then
            echo "Canvas is accessible and showing content (HTTP $HTTP_CODE) after ${elapsed}s"
            return 0
        fi

        # Also accept if we get a valid redirect to login
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
            # Double-check the login page is actually accessible
            local login_response=$(curl -s -L --connect-timeout 10 "http://localhost:3000/login/canvas" 2>/dev/null | head -c 2000)
            if echo "$login_response" | grep -qi "canvas\|Log In\|password" 2>/dev/null; then
                echo "Canvas login page is accessible (HTTP $HTTP_CODE) after ${elapsed}s"
                return 0
            fi
        fi

        # Log progress every 15 seconds
        if [ $((elapsed % 15)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            echo "  Still waiting for Canvas... ${elapsed}s (HTTP $HTTP_CODE)"
            # Show docker status periodically
            if [ $((elapsed % 30)) -eq 0 ]; then
                docker ps --format "{{.Names}}: {{.Status}}" 2>/dev/null | grep -i canvas || true
            fi
        fi

        sleep $backoff
        elapsed=$((elapsed + backoff))

        # Exponential backoff up to 5 seconds
        if [ $backoff -lt 5 ]; then
            backoff=$((backoff + 1))
        fi
    done

    echo "WARNING: Canvas not accessible after ${timeout}s (last HTTP code: $HTTP_CODE)"
    return 1
}

# Comprehensive pre-task check: Canvas accessible + Firefox running + page loaded
# Args: $1 - max retries for page refresh (default: 5)
# Returns: 0 if ready, 1 if not
ensure_canvas_ready_for_task() {
    local max_retries=${1:-5}
    local canvas_url="http://localhost:3000/login/canvas"

    echo "=== Pre-Task Canvas Health Check (Enhanced) ==="

    # Step 1: Check if Canvas server is accessible (increased timeout to 180s)
    if ! wait_for_canvas_ready 180; then
        echo "CRITICAL: Canvas server is not responding after 180 seconds"
        echo "The agent should wait and retry, or the environment may need restart"

        # Try to show Docker container status
        echo "Checking Docker container status..."
        docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -i canvas || true
        docker logs canvas-lms --tail 30 2>/dev/null || true

        # Last resort: try to restart Canvas services
        echo "Attempting to restart Canvas services..."
        docker exec canvas-lms sv restart apache2 2>/dev/null || true
        sleep 30

        # Final check
        if ! wait_for_canvas_ready 60; then
            echo "CRITICAL: Canvas still not responding after service restart"
            return 1
        fi
    fi

    # Step 2: Ensure Firefox is running
    echo "Checking Firefox..."
    if ! pgrep -f firefox > /dev/null; then
        echo "Firefox not running, starting it..."
        su - ga -c "DISPLAY=:1 firefox '$canvas_url' > /tmp/firefox_task.log 2>&1 &"
        sleep 8
    fi

    # Step 3: Wait for Firefox window to appear with increased timeout
    if ! wait_for_window "firefox\|mozilla" 45; then
        echo "WARNING: Firefox window not detected, attempting to restart..."
        pkill -9 -f firefox 2>/dev/null || true
        sleep 3
        su - ga -c "DISPLAY=:1 firefox '$canvas_url' > /tmp/firefox_task.log 2>&1 &"
        sleep 10

        if ! wait_for_window "firefox\|mozilla" 30; then
            echo "CRITICAL: Cannot start Firefox"
            return 1
        fi
    fi

    # Step 4: Focus and maximize Firefox
    local wid=$(get_firefox_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 1
    fi

    # Step 5: Navigate to Canvas login page and verify it loads
    echo "Navigating to Canvas login page..."
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool type "$canvas_url" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5

    # Step 6: Refresh and verify page loads correctly with exponential backoff
    echo "Verifying Canvas page loads correctly..."
    local backoff_time=3
    for retry in $(seq 1 $max_retries); do
        # Send F5 to refresh
        DISPLAY=:1 xdotool key F5 2>/dev/null || true
        sleep $backoff_time

        # Take a test screenshot
        local test_screenshot="/tmp/canvas_health_check_$$.png"
        take_screenshot "$test_screenshot"

        # Check if Canvas login page content is accessible
        local login_response=$(curl -s -L --connect-timeout 10 "$canvas_url" 2>/dev/null | head -c 3000)
        if echo "$login_response" | grep -qi "canvas\|Log In\|password\|email" 2>/dev/null; then
            echo "  Canvas login page verified (attempt $retry)"

            # Additional verification: wait a bit more and take final screenshot
            sleep 3
            take_screenshot "$test_screenshot"

            # Verify again to ensure page is fully loaded
            local final_check=$(curl -s -L --connect-timeout 10 "$canvas_url" 2>/dev/null | head -c 3000)
            if echo "$final_check" | grep -qi "Log In\|password" 2>/dev/null; then
                echo "Canvas health check PASSED - login page verified"
                rm -f "$test_screenshot" 2>/dev/null
                return 0
            fi
        fi

        echo "  Retry $retry of $max_retries - page not ready yet, waiting ${backoff_time}s..."

        # Exponential backoff: 3, 5, 8, 12, 15 seconds
        backoff_time=$((backoff_time + retry + 1))
        if [ $backoff_time -gt 15 ]; then
            backoff_time=15
        fi
        sleep $backoff_time
    done

    # Final fallback check
    local final_response=$(curl -s -L --connect-timeout 15 "$canvas_url" 2>/dev/null | head -c 3000)
    if echo "$final_response" | grep -qi "canvas\|Log In\|password" 2>/dev/null; then
        echo "Canvas health check PASSED (final verification)"
        return 0
    fi

    echo "WARNING: Canvas health check completed but page content could not be fully verified"
    echo "The agent may encounter 'connection reset' errors - tasks should handle this gracefully"
    return 1
}

# ── Ensure Canvas Docker container is running ────────────────────────────
# Critical when loading from QEMU checkpoint — Docker containers that were
# running during checkpoint creation are NOT running when restored.
ensure_canvas_running() {
    local canvas_url="http://localhost:3000/"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 -L "$canvas_url" 2>/dev/null || echo "000")
    if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "303" ]; then
        echo "Canvas LMS already running (HTTP $http_code)"
        return 0
    fi

    echo "Canvas LMS not responding (HTTP $http_code). Starting services..."

    # Ensure swap is active (Canvas fat container is memory-hungry)
    if [ -f /swapfile ]; then
        swapon /swapfile 2>/dev/null || true
    fi

    # Ensure Docker daemon is running
    systemctl is-active docker >/dev/null 2>&1 || {
        echo "Starting Docker daemon..."
        systemctl start docker
        sleep 5
    }

    # Start Canvas container
    local CANVAS_DIR="/home/ga/canvas"
    if [ -f "$CANVAS_DIR/docker-compose.yml" ]; then
        echo "Starting Canvas container..."
        cd "$CANVAS_DIR"
        docker-compose up -d 2>&1 || docker compose up -d 2>&1 || true
        cd - >/dev/null
    else
        echo "ERROR: docker-compose.yml not found at $CANVAS_DIR"
        return 1
    fi

    # Wait for Canvas (fat container takes time for Rails to boot)
    echo "Waiting for Canvas LMS to start (Rails boot may take 1-3 min)..."
    local timeout=300
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 -L "$canvas_url" 2>/dev/null || echo "000")
        if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "303" ]; then
            echo "Canvas LMS is ready after ${elapsed}s (HTTP $http_code)"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  Still waiting for Canvas... ${elapsed}s (HTTP $http_code)"
            docker ps --format "{{.Names}}: {{.Status}}" 2>/dev/null | grep -i canvas || true
        fi
    done

    echo "WARNING: Canvas may not be ready after ${timeout}s"
    return 0
}

# Auto-start services when task_utils.sh is sourced
ensure_canvas_running

export -f ensure_canvas_running
export -f wait_for_canvas_ready
export -f ensure_canvas_ready_for_task

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
export -f _get_canvas_method
export -f canvas_query
export -f canvas_query_headers
export -f get_user_count
export -f get_user_by_login
export -f user_exists
export -f get_course_count
export -f course_exists
export -f get_course_by_code
export -f get_course_by_name
export -f get_course_by_id
export -f is_user_enrolled
export -f get_enrollment_count
export -f get_assignment_count
export -f get_assignment_by_title
export -f get_module_count
export -f get_module_by_name
export -f get_announcement_count
export -f get_announcement_by_title
export -f wait_for_window
export -f wait_for_file
export -f focus_window
export -f get_firefox_window_id
export -f take_screenshot
export -f safe_write_json
