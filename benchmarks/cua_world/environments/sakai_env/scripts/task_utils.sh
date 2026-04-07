#!/bin/bash
# Shared utilities for Sakai task setup and export scripts

# =============================================================================
# Auto-check: wait for Sakai web service on source
# This ensures web service is ready after cache restore
# =============================================================================
echo "Checking Sakai web service readiness..."

# Source environment
source /etc/profile.d/java.sh 2>/dev/null || true
source /etc/profile.d/tomcat.sh 2>/dev/null || true
export CATALINA_HOME="${CATALINA_HOME:-/opt/tomcat}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"

_sakai_ready=false
for _sakai_check_i in $(seq 1 90); do
    _sakai_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/portal" 2>/dev/null || echo "000")
    if [ "$_sakai_code" = "200" ] || [ "$_sakai_code" = "302" ] || [ "$_sakai_code" = "301" ]; then
        echo "Sakai web service is ready"
        _sakai_ready=true
        break
    fi
    # At 60s mark, try restarting Docker containers and Tomcat
    if [ "$_sakai_check_i" -eq 20 ]; then
        echo "Sakai not responding after 60s, restarting services..."
        docker compose -f /home/ga/sakai/docker-compose.yml restart 2>/dev/null || true
        su - ga -c "export JAVA_HOME=$JAVA_HOME && export CATALINA_HOME=$CATALINA_HOME && $CATALINA_HOME/bin/shutdown.sh" 2>/dev/null || true
        sleep 5
        su - ga -c "export JAVA_HOME=$JAVA_HOME && export CATALINA_HOME=$CATALINA_HOME && $CATALINA_HOME/bin/startup.sh" 2>/dev/null || true
    fi
    sleep 3
done
if [ "$_sakai_ready" != "true" ]; then
    echo "WARNING: Sakai not ready after 270s, forcing restart..."
    docker compose -f /home/ga/sakai/docker-compose.yml restart 2>/dev/null || true
    su - ga -c "export JAVA_HOME=$JAVA_HOME && export CATALINA_HOME=$CATALINA_HOME && $CATALINA_HOME/bin/shutdown.sh" 2>/dev/null || true
    sleep 5
    su - ga -c "export JAVA_HOME=$JAVA_HOME && export CATALINA_HOME=$CATALINA_HOME && $CATALINA_HOME/bin/startup.sh" 2>/dev/null || true
    sleep 30
fi

# =============================================================================
# Database Utilities
# =============================================================================

# Execute SQL query against Sakai database (no headers, tab-separated)
# Args: $1 - SQL query
# Returns: query result (tab-separated, no column headers)
sakai_query() {
    local query="$1"
    docker exec sakai-db mysql -u sakai -psakaipass sakai -N -B -e "$query" 2>/dev/null
}

# Execute SQL query with column headers
sakai_query_headers() {
    local query="$1"
    docker exec sakai-db mysql -u sakai -psakaipass sakai -e "$query" 2>/dev/null
}

# =============================================================================
# Sakai REST API Utilities
# =============================================================================

# Get admin session ID
get_admin_session() {
    local session
    session=$(curl -s -X POST "http://localhost:8080/sakai-ws/rest/login/login" \
        -d "id=admin" -d "pw=admin" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$session" ] && [ "$session" != "null" ]; then
        echo "$session"
    else
        echo "" >&2
        echo "ERROR: Could not get admin session" >&2
        return 1
    fi
}

# Make authenticated REST API call
# Args: $1 - method (GET/POST), $2 - endpoint path, $3 - session ID, $4 - data (optional)
sakai_api() {
    local method="$1"
    local endpoint="$2"
    local session="$3"
    local data="$4"

    if [ "$method" = "GET" ]; then
        curl -s -X GET "http://localhost:8080${endpoint}" \
            -H "Cookie: SAKAI_SESSION=$session" 2>/dev/null
    else
        curl -s -X POST "http://localhost:8080${endpoint}" \
            -H "Cookie: SAKAI_SESSION=$session" \
            -d "$data" 2>/dev/null
    fi
}

# =============================================================================
# Site Query Utilities
# =============================================================================

# Get total site count (excluding special sites)
get_site_count() {
    sakai_query "SELECT COUNT(*) FROM SAKAI_SITE WHERE SITE_ID NOT LIKE '~%' AND SITE_ID NOT LIKE '!%'"
}

# Check if a site exists by ID
# Args: $1 - site ID
# Returns: 0 if found, 1 if not
site_exists() {
    local site_id="$1"
    local count
    count=$(sakai_query "SELECT COUNT(*) FROM SAKAI_SITE WHERE SITE_ID='$site_id'")
    [ "${count:-0}" -gt 0 ]
}

# Get site by ID
# Args: $1 - site ID
# Returns: tab-separated: SITE_ID, TITLE, TYPE, PUBLISHED
get_site_by_id() {
    local site_id="$1"
    sakai_query "SELECT SITE_ID, TITLE, TYPE, PUBLISHED FROM SAKAI_SITE WHERE SITE_ID='$site_id' LIMIT 1"
}

# Get site by title (case-insensitive partial match)
# Args: $1 - title pattern
get_site_by_title() {
    local title="$1"
    sakai_query "SELECT SITE_ID, TITLE, TYPE, PUBLISHED FROM SAKAI_SITE WHERE LOWER(TITLE) LIKE LOWER('%$title%') AND SITE_ID NOT LIKE '~%' AND SITE_ID NOT LIKE '!%' LIMIT 1"
}

# Get assignment count for a site
# Args: $1 - site context (site ID)
get_assignment_count() {
    local site_id="$1"
    sakai_query "SELECT COUNT(*) FROM ASN_ASSIGNMENT WHERE CONTEXT='$site_id' AND DELETED=0" 2>/dev/null || echo "0"
}

# Get announcement count for a site
# Args: $1 - site ID
get_announcement_count() {
    local site_id="$1"
    sakai_query "SELECT COUNT(*) FROM ANNOUNCEMENT_MESSAGE WHERE CHANNEL_ID LIKE '%/channel/$site_id/main%'" 2>/dev/null || echo "0"
}

# Get membership count for a site
# Args: $1 - site ID
get_membership_count() {
    local site_id="$1"
    sakai_query "SELECT COUNT(*) FROM SAKAI_SITE_USER WHERE SITE_ID='$site_id'"
}

# Get tools for a site
# Args: $1 - site ID
get_site_tools() {
    local site_id="$1"
    sakai_query "SELECT REGISTRATION FROM SAKAI_SITE_TOOL WHERE SITE_ID='$site_id'" 2>/dev/null || echo ""
}

# =============================================================================
# Web Service Wait
# =============================================================================

wait_for_sakai() {
    local timeout=${1:-120}
    local elapsed=0
    local restarted=false
    echo "Waiting for Sakai web service..." >&2
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/portal" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            echo "Sakai is ready (HTTP $HTTP_CODE) after ${elapsed}s" >&2
            return 0
        fi
        if [ "$restarted" = "false" ] && [ $elapsed -ge 60 ]; then
            echo "Sakai not responding after ${elapsed}s, restarting..." >&2
            docker compose -f /home/ga/sakai/docker-compose.yml restart 2>/dev/null || true
            su - ga -c "export JAVA_HOME=$JAVA_HOME && export CATALINA_HOME=$CATALINA_HOME && $CATALINA_HOME/bin/shutdown.sh" 2>/dev/null || true
            sleep 5
            su - ga -c "export JAVA_HOME=$JAVA_HOME && export CATALINA_HOME=$CATALINA_HOME && $CATALINA_HOME/bin/startup.sh" 2>/dev/null || true
            restarted=true
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "WARNING: Sakai not ready after ${timeout}s" >&2
    return 1
}

# =============================================================================
# Firefox / Window Management
# =============================================================================

restart_firefox() {
    local url="${1:-http://localhost:8080/portal}"

    wait_for_sakai 120 || echo "WARNING: Sakai may not be ready" >&2

    pkill -9 -f firefox 2>/dev/null || true
    sleep 3

    # Use auto-login helper if navigating to portal (logs in as admin automatically)
    if echo "$url" | grep -q "localhost:8080/portal"; then
        local login_html="/home/ga/snap/firefox/common/sakai_login.html"
        if [ -f "$login_html" ]; then
            su - ga -c "export DISPLAY=:1 && setsid firefox '$login_html' > /tmp/firefox_sakai.log 2>&1 &"
        else
            su - ga -c "export DISPLAY=:1 && setsid firefox '$url' > /tmp/firefox_sakai.log 2>&1 &"
        fi
    else
        su - ga -c "export DISPLAY=:1 && setsid firefox '$url' > /tmp/firefox_sakai.log 2>&1 &"
    fi

    # Snap Firefox takes 15-30s to start
    local ff_started=false
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|sakai"; then
            ff_started=true
            echo "Firefox window detected after ${i}s" >&2
            break
        fi
        sleep 1
    done

    if [ "$ff_started" = true ]; then
        sleep 5
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi

    # After auto-login, navigate to the requested URL
    if [ -f "/home/ga/snap/firefox/common/sakai_login.html" ] && echo "$url" | grep -q "localhost:8080"; then
        sleep 5
        DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
        sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers "$url" 2>/dev/null || true
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 8
    fi
}

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
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'
}

focus_window() {
    local window_id="$1"
    DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null || true
    sleep 0.3
}

take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
    echo "Warning: Could not take screenshot" >&2
    [ -f "$output_file" ] && echo "Screenshot saved: $output_file" >&2
}

# =============================================================================
# JSON Export Utilities
# =============================================================================

safe_write_json() {
    local temp_file="$1"
    local dest_path="$2"
    rm -f "$dest_path" 2>/dev/null || sudo rm -f "$dest_path" 2>/dev/null || true
    cp "$temp_file" "$dest_path" 2>/dev/null || sudo cp "$temp_file" "$dest_path"
    chmod 666 "$dest_path" 2>/dev/null || sudo chmod 666 "$dest_path" 2>/dev/null || true
    rm -f "$temp_file"
    echo "Result saved to $dest_path" >&2
}

# =============================================================================
# Export functions
# =============================================================================
export -f sakai_query
export -f sakai_query_headers
export -f get_admin_session
export -f sakai_api
export -f get_site_count
export -f site_exists
export -f get_site_by_id
export -f get_site_by_title
export -f get_assignment_count
export -f get_announcement_count
export -f get_membership_count
export -f get_site_tools
export -f wait_for_sakai
export -f restart_firefox
export -f wait_for_window
export -f get_firefox_window_id
export -f focus_window
export -f take_screenshot
export -f safe_write_json
