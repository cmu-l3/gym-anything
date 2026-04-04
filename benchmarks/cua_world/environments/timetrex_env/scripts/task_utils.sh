#!/bin/bash
# Shared utilities for TimeTrex task setup and export scripts

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
# Returns: 0 if file exists and was recently modified, 1 if timeout
wait_for_file() {
    local filepath="$1"
    local timeout=${2:-10}
    local start=$(date +%s)

    echo "Waiting for file: $filepath"

    while [ $(($(date +%s) - start)) -lt $timeout ]; do
        if [ -f "$filepath" ]; then
            if [ $(find "$filepath" -mmin -0.2 2>/dev/null | wc -l) -gt 0 ] || \
               [ $(($(date +%s) - start)) -lt 2 ]; then
                echo "File ready: $filepath"
                return 0
            fi
        fi
        sleep 0.5
    done

    echo "Timeout: File not updated: $filepath"
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
            echo "Process found after ${elapsed}s"
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: Process not found after ${timeout}s"
    return 1
}

# Focus a window and verify it was focused
# Args: $1 - window ID or name pattern
# Returns: 0 if focused successfully, 1 otherwise
focus_window() {
    local window_id="$1"

    if DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null || DISPLAY=:1 wmctrl -a "$window_id" 2>/dev/null; then
        sleep 0.3
        if DISPLAY=:1 wmctrl -lpG 2>/dev/null | grep -q "$window_id"; then
            echo "Window focused: $window_id"
            return 0
        fi
    fi

    echo "Failed to focus window: $window_id"
    return 1
}

# Get the window ID for Firefox
# Returns: window ID or empty string
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'
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

# Ensure Docker containers are running
# This is needed when loading from checkpoint since containers don't auto-restart
# CRITICAL: This function must reliably start TimeTrex and verify it's accessible
# AGGRESSIVE: Uses many retries and long waits - this MUST work or task cannot proceed
ensure_docker_containers() {
    echo "=== Ensuring Docker containers are running ==="
    echo "Timestamp: $(date -Iseconds)"

    local MAX_RETRIES=10
    local retry=0
    local TIMETREX_DIR="/home/ga/timetrex"

    # Verify critical paths exist
    if [ ! -d "$TIMETREX_DIR" ]; then
        echo "CRITICAL ERROR: $TIMETREX_DIR does not exist!"
        echo "Creating directory and copying config files..."
        mkdir -p "$TIMETREX_DIR"
        cp /workspace/config/docker-compose.yml "$TIMETREX_DIR/" 2>/dev/null || true
        cp /workspace/config/Dockerfile.timetrex "$TIMETREX_DIR/" 2>/dev/null || true
        cp /workspace/config/timetrex.ini.php "$TIMETREX_DIR/" 2>/dev/null || true
        chown -R ga:ga "$TIMETREX_DIR" 2>/dev/null || true
    fi

    while [ $retry -lt $MAX_RETRIES ]; do
        retry=$((retry + 1))
        echo ""
        echo "========== Attempt $retry of $MAX_RETRIES =========="

        # Step 1: Ensure Docker daemon is running
        echo "[Step 1/6] Checking Docker daemon..."
        local docker_running=false

        # Try multiple methods to check/start Docker
        if systemctl is-active --quiet docker 2>/dev/null; then
            docker_running=true
        elif service docker status >/dev/null 2>&1; then
            docker_running=true
        elif docker info >/dev/null 2>&1; then
            docker_running=true
        fi

        if [ "$docker_running" = false ]; then
            echo "Docker daemon not running, starting it..."

            # Try systemd first
            systemctl start docker 2>/dev/null &
            sleep 5

            # Try service command
            service docker start 2>/dev/null &
            sleep 5

            # If still not running, try dockerd directly
            if ! docker info >/dev/null 2>&1; then
                echo "Trying dockerd directly..."
                nohup dockerd > /var/log/dockerd.log 2>&1 &
                sleep 10
            fi

            # Wait for Docker to be ready (up to 60 seconds)
            echo "Waiting for Docker daemon to respond..."
            for i in {1..60}; do
                if docker info >/dev/null 2>&1; then
                    echo "Docker daemon started after ${i}s"
                    docker_running=true
                    break
                fi
                [ $((i % 10)) -eq 0 ] && echo "  Still waiting for Docker... ${i}s"
                sleep 1
            done
        fi

        if [ "$docker_running" = false ]; then
            echo "ERROR: Docker daemon not responding"
            continue
        fi
        echo "OK: Docker daemon is running"

        # Step 2: Check container status and start if needed
        echo "[Step 2/6] Checking container status..."
        cd "$TIMETREX_DIR" || { echo "ERROR: Cannot cd to $TIMETREX_DIR"; continue; }

        local pg_running=$(docker ps -q -f name=timetrex-postgres -f status=running 2>/dev/null)
        local app_running=$(docker ps -q -f name=timetrex-app -f status=running 2>/dev/null)

        if [ -z "$pg_running" ] || [ -z "$app_running" ]; then
            echo "Containers not running. Current status:"
            docker ps -a --filter name=timetrex 2>/dev/null || true

            # Remove stopped containers
            echo "Removing any stopped containers..."
            docker-compose down --remove-orphans 2>/dev/null || true
            docker rm -f timetrex-postgres timetrex-app 2>/dev/null || true
            sleep 2

            # Check if images exist, build if not
            if ! docker images --format "{{.Repository}}" 2>/dev/null | grep -q "timetrex"; then
                echo "Docker images not found, building (this may take a while)..."
                if ! docker-compose build 2>&1; then
                    echo "ERROR: docker-compose build failed"
                    docker-compose logs 2>&1 | tail -30
                    continue
                fi
            fi

            # Start containers with explicit wait
            echo "Starting containers with docker-compose up -d..."
            if ! docker-compose up -d 2>&1; then
                echo "ERROR: docker-compose up failed"
                docker-compose logs 2>&1 | tail -30
                continue
            fi

            echo "Waiting for containers to initialize..."
            sleep 10

            # Verify containers are now running
            pg_running=$(docker ps -q -f name=timetrex-postgres -f status=running 2>/dev/null)
            app_running=$(docker ps -q -f name=timetrex-app -f status=running 2>/dev/null)

            if [ -z "$pg_running" ] || [ -z "$app_running" ]; then
                echo "ERROR: Containers failed to start"
                docker-compose ps 2>/dev/null
                docker-compose logs --tail=50 2>&1
                continue
            fi
        fi
        echo "OK: Both containers are running"
        docker-compose ps 2>/dev/null

        # Step 3: Wait for PostgreSQL to accept connections
        echo "[Step 3/6] Waiting for PostgreSQL to accept connections..."
        local pg_ready=false
        for i in {1..90}; do
            if docker exec timetrex-postgres pg_isready -U timetrex -d timetrex 2>/dev/null; then
                echo "OK: PostgreSQL ready after ${i}s"
                pg_ready=true
                break
            fi
            [ $((i % 10)) -eq 0 ] && echo "  Still waiting for PostgreSQL... ${i}s"
            sleep 1
        done

        if [ "$pg_ready" = false ]; then
            echo "ERROR: PostgreSQL not ready after 90s"
            docker logs timetrex-postgres 2>&1 | tail -30
            continue
        fi

        # Step 4: Verify database exists and has tables
        echo "[Step 4/6] Verifying database structure..."
        local table_count=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null | tr -d ' ')

        if [ -z "$table_count" ] || [ "$table_count" = "0" ]; then
            echo "Database has no tables. Running TimeTrex installer..."

            # Try the unattended installer
            docker exec timetrex-app php /var/www/html/timetrex/tools/unattended_install.php 2>&1 || {
                echo "Unattended installer failed, trying CLI install..."
                docker exec timetrex-app php /var/www/html/timetrex/tools/install/install.php \
                    --installer_db=postgres \
                    --installer_db_host=postgres \
                    --installer_db_user=timetrex \
                    --installer_db_password=timetrex \
                    --installer_db_database=timetrex \
                    --installer_email=admin@example.com \
                    --installer_password=admin \
                    --installer_company_name="Demo Company" \
                    --installer_first_name=Admin \
                    --installer_last_name=User 2>&1 || true
            }
            sleep 5

            table_count=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null | tr -d ' ')
            if [ -z "$table_count" ] || [ "$table_count" = "0" ]; then
                echo "ERROR: Database still has no tables after install attempt"
                continue
            fi
        fi
        echo "OK: Database has $table_count tables"

        # Step 5: Wait for web interface to be accessible
        echo "[Step 5/6] Waiting for TimeTrex web interface..."
        local web_ready=false
        for i in {1..180}; do
            local HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost/interface/Login.php 2>/dev/null)
            if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
                echo "OK: TimeTrex web interface ready after ${i}s (HTTP $HTTP_CODE)"
                web_ready=true
                break
            fi
            [ $((i % 15)) -eq 0 ] && echo "  Still waiting for web interface... ${i}s (HTTP $HTTP_CODE)"
            sleep 1
        done

        if [ "$web_ready" = false ]; then
            echo "ERROR: TimeTrex web interface not accessible after 180s"
            echo "Last HTTP code: $HTTP_CODE"
            docker logs timetrex-app 2>&1 | tail -50
            continue
        fi

        # Step 6: Verify demo data exists
        echo "[Step 6/6] Verifying demo data..."
        local user_count=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "SELECT COUNT(*) FROM users" 2>/dev/null | tr -d ' ')

        if [ -z "$user_count" ] || [ "$user_count" -lt 5 ]; then
            echo "Insufficient demo data (user count: ${user_count:-0}), generating..."

            # Try using built-in demo data generator
            docker exec timetrex-app php /var/www/html/timetrex/tools/create_demo_data.php 2>&1 || {
                echo "Built-in generator failed, trying DemoData class..."
                docker exec timetrex-app php -r "
                    require_once '/var/www/html/timetrex/classes/DemoData.class.php';
                    \$d = new DemoData();
                    \$d->UserNamePostFix = 1;
                    \$d->createDemoData();
                    echo 'Demo data created\n';
                " 2>&1 || true
            }

            sleep 5
            user_count=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "SELECT COUNT(*) FROM users" 2>/dev/null | tr -d ' ')
            echo "User count after demo data: $user_count"
        fi
        echo "OK: Database has $user_count users"

        # Verify critical employees exist
        local john_exists=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "SELECT COUNT(*) FROM users WHERE first_name='John' AND last_name='Doe'" 2>/dev/null | tr -d ' ')
        local jane_exists=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "SELECT COUNT(*) FROM users WHERE first_name='Jane' AND last_name='Doe'" 2>/dev/null | tr -d ' ')
        local heather_exists=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "SELECT COUNT(*) FROM users WHERE first_name='Heather' AND last_name='Grant'" 2>/dev/null | tr -d ' ')

        echo "Critical employees: John Doe=$john_exists, Jane Doe=$jane_exists, Heather Grant=$heather_exists"

        echo ""
        echo "=== Docker containers started and verified successfully ==="
        echo "Timestamp: $(date -Iseconds)"
        return 0
    done

    echo ""
    echo "=== CRITICAL ERROR: Failed to start Docker containers after $MAX_RETRIES attempts ==="
    echo "Please check Docker installation and container configuration"
    return 1
}
export -f ensure_docker_containers

# Execute SQL query against TimeTrex PostgreSQL database (via Docker)
# Args: $1 - SQL query
# Returns: query result
timetrex_query() {
    local query="$1"
    docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "$query" 2>/dev/null | tr -d ' '
}

# Execute SQL query and return full result (with formatting)
timetrex_query_full() {
    local query="$1"
    docker exec timetrex-postgres psql -U timetrex -d timetrex -c "$query" 2>/dev/null
}

# Get user count from database
get_user_count() {
    timetrex_query "SELECT COUNT(*) FROM users"
}

# Get employee count from database
get_employee_count() {
    timetrex_query "SELECT COUNT(*) FROM users WHERE status_id=10"
}

# Check if user exists by name
# Args: $1 - first name, $2 - last name
# Returns: 0 if found, 1 if not found
user_exists() {
    local fname="$1"
    local lname="$2"
    local count=$(timetrex_query "SELECT COUNT(*) FROM users WHERE LOWER(first_name)=LOWER('$fname') AND LOWER(last_name)=LOWER('$lname')")
    [ "$count" -gt 0 ]
}

# Get punch count from database
get_punch_count() {
    timetrex_query "SELECT COUNT(*) FROM punch"
}

# Get schedule count from database
get_schedule_count() {
    timetrex_query "SELECT COUNT(*) FROM schedule"
}

# Take a screenshot
# Args: $1 - output file path (default: /tmp/screenshot.png)
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    # Use ImageMagick's import command (more reliable than scrot)
    DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
    echo "Warning: Could not take screenshot"
    [ -f "$output_file" ] && echo "Screenshot saved: $output_file"
}

# Verify TimeTrex login page is accessible
# Returns: 0 if accessible, 1 if not
verify_timetrex_accessible() {
    local HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://localhost/interface/Login.php 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "TimeTrex login page accessible (HTTP $HTTP_CODE)"
        return 0
    else
        echo "ERROR: TimeTrex login page NOT accessible (HTTP $HTTP_CODE)"
        return 1
    fi
}

# Verify an employee exists in the database - STRICT (returns 1 if not found)
# Args: $1 - first name, $2 - last name, $3 - employee number (optional)
# Returns: 0 if found, 1 if not found
verify_employee_exists() {
    local fname="$1"
    local lname="$2"
    local emp_num="$3"

    local count
    if [ -n "$emp_num" ]; then
        count=$(timetrex_query "SELECT COUNT(*) FROM users WHERE LOWER(first_name)=LOWER('$fname') AND LOWER(last_name)=LOWER('$lname') AND employee_number='$emp_num'")
    else
        count=$(timetrex_query "SELECT COUNT(*) FROM users WHERE LOWER(first_name)=LOWER('$fname') AND LOWER(last_name)=LOWER('$lname')")
    fi

    if [ "$count" -gt 0 ] 2>/dev/null; then
        echo "OK: Employee '$fname $lname' ${emp_num:+(#$emp_num) }found in database"
        return 0
    else
        echo "FATAL: Employee '$fname $lname' ${emp_num:+(#$emp_num) }NOT found in database!"
        return 1
    fi
}

# Pre-flight check for tasks - ensures environment is ready
# Returns: 0 if ready, 1 if not
# CRITICAL: This is the LAST LINE OF DEFENSE - if this fails, task CANNOT proceed
preflight_check() {
    echo "=============================================="
    echo "=== Running Pre-flight Check (AGGRESSIVE) ==="
    echo "=============================================="
    echo "Timestamp: $(date -Iseconds)"

    # Step 1: Run ensure_docker_containers (with aggressive retries)
    echo ""
    echo "[PREFLIGHT Step 1/5] Starting Docker containers..."
    if ! ensure_docker_containers; then
        echo "FATAL: Docker containers failed to start after all retry attempts"
        echo "This is a critical infrastructure failure. Cannot proceed."
        return 1
    fi

    # Step 2: Wait for web interface with extended timeout (up to 5 minutes)
    echo ""
    echo "[PREFLIGHT Step 2/5] Verifying TimeTrex web interface (up to 300s)..."
    local web_ready=false
    for i in {1..300}; do
        local HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost/interface/Login.php 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "OK: TimeTrex web interface ready after ${i}s (HTTP $HTTP_CODE)"
            web_ready=true
            break
        fi
        [ $((i % 30)) -eq 0 ] && echo "  Still waiting for web interface... ${i}s (HTTP $HTTP_CODE)"
        sleep 1
    done

    if [ "$web_ready" = false ]; then
        echo "FATAL: TimeTrex web interface not accessible after 300 seconds"
        echo "Last HTTP code: $HTTP_CODE"
        echo "Container logs:"
        docker logs timetrex-app 2>&1 | tail -30 || true
        return 1
    fi

    # Step 3: Kill any existing Firefox and restart fresh
    echo ""
    echo "[PREFLIGHT Step 3/5] Restarting Firefox with TimeTrex login page..."
    pkill -f firefox 2>/dev/null || true
    sleep 2

    # Launch Firefox pointing directly at login page
    su - ga -c "DISPLAY=:1 firefox --new-window 'http://localhost/interface/Login.php' > /tmp/firefox_task.log 2>&1 &"

    # Wait for Firefox window to appear (up to 60 seconds)
    echo "Waiting for Firefox window..."
    local firefox_found=false
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
            echo "Firefox window detected after ${i}s"
            firefox_found=true
            break
        fi
        sleep 1
    done

    if [ "$firefox_found" = false ]; then
        echo "WARNING: Firefox window not detected after 60s, trying again..."
        su - ga -c "DISPLAY=:1 firefox 'http://localhost/interface/Login.php' > /tmp/firefox_task2.log 2>&1 &"
        sleep 10
    fi

    # Step 4: Focus and maximize Firefox window
    echo ""
    echo "[PREFLIGHT Step 4/5] Focusing and maximizing Firefox..."
    sleep 3  # Give Firefox time to load the page
    local WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "Firefox window focused and maximized (WID: $WID)"
    else
        echo "WARNING: Could not get Firefox window ID, trying wmctrl -a..."
        DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || DISPLAY=:1 wmctrl -a "Mozilla" 2>/dev/null || true
    fi

    # Step 5: Wait for page to fully load and verify login page is visible
    echo ""
    echo "[PREFLIGHT Step 5/5] Waiting for login page to load in Firefox..."
    sleep 5  # Give the page time to render

    # Take a verification screenshot
    DISPLAY=:1 import -window root /tmp/preflight_screenshot.png 2>/dev/null || true
    if [ -f /tmp/preflight_screenshot.png ]; then
        echo "Pre-flight screenshot saved to /tmp/preflight_screenshot.png"
    fi

    # Final HTTP check
    local FINAL_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost/interface/Login.php 2>/dev/null)
    if [ "$FINAL_HTTP" != "200" ] && [ "$FINAL_HTTP" != "302" ]; then
        echo "FATAL: Final HTTP check failed (HTTP $FINAL_HTTP)"
        return 1
    fi

    echo ""
    echo "=============================================="
    echo "=== Pre-flight Check PASSED ==="
    echo "=============================================="
    echo "Timestamp: $(date -Iseconds)"
    echo "TimeTrex is accessible at http://localhost/interface/Login.php"
    echo ""
    return 0
}

# Export these functions for use in other scripts
export -f wait_for_window
export -f wait_for_file
export -f wait_for_process
export -f focus_window
export -f get_firefox_window_id
export -f safe_xdotool
export -f timetrex_query
export -f timetrex_query_full
export -f get_user_count
export -f get_employee_count
export -f user_exists
export -f get_punch_count
export -f get_schedule_count
export -f take_screenshot
export -f verify_timetrex_accessible
export -f verify_employee_exists
export -f preflight_check
