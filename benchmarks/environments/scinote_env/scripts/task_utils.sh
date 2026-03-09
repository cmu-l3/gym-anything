#!/bin/bash
# Shared utilities for all SciNote tasks

SCINOTE_URL="http://localhost:3000"
SCINOTE_ADMIN_EMAIL="admin@scinote.net"
SCINOTE_ADMIN_PASSWORD="inHisHouseAtRlyehDeadCthulhuWaitsDreaming"

# ============================================================
# Window management utilities
# ============================================================

wait_for_window() {
    local pattern="$1"
    local timeout="${2:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done
    return 1
}

focus_window() {
    local wid="$1"
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
}

get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla\|scinote" | head -1 | awk '{print $1}'
}

# ============================================================
# Screenshot utility
# ============================================================

take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# ============================================================
# Database query utility (via Docker)
# ============================================================

scinote_db_query() {
    local query="$1"
    docker exec scinote_db psql -U postgres -d scinote_production -t -A -c "$query" 2>/dev/null
}

# ============================================================
# Rails console query utility
# ============================================================

scinote_rails_query() {
    local ruby_code="$1"
    docker exec scinote_web bash -c "bundle exec rails runner \"$ruby_code\"" 2>/dev/null
}

# ============================================================
# Count utilities
# ============================================================

get_project_count() {
    scinote_db_query "SELECT COUNT(*) FROM projects;" | tr -d '[:space:]'
}

get_experiment_count() {
    scinote_db_query "SELECT COUNT(*) FROM experiments;" | tr -d '[:space:]'
}

get_my_module_count() {
    scinote_db_query "SELECT COUNT(*) FROM my_modules;" | tr -d '[:space:]'
}

get_protocol_count() {
    scinote_db_query "SELECT COUNT(*) FROM protocols WHERE protocol_type IN (2, 3, 4, 5, 6, 7);" | tr -d '[:space:]'
}

get_repository_count() {
    scinote_db_query "SELECT COUNT(*) FROM repositories;" | tr -d '[:space:]'
}

get_repository_row_count() {
    local repo_name="$1"
    scinote_db_query "SELECT COUNT(*) FROM repository_rows rr JOIN repositories r ON rr.repository_id = r.id WHERE LOWER(r.name) LIKE LOWER('%${repo_name}%');" | tr -d '[:space:]'
}

# ============================================================
# Docker & SciNote health checks
# ============================================================

ensure_docker_healthy() {
    # Ensure Docker daemon is running
    if ! systemctl is-active --quiet docker 2>/dev/null; then
        echo "Docker not running, starting..."
        systemctl start docker
        sleep 3
    fi

    # Check if SciNote containers are running, restart if needed
    local web_running db_running
    web_running=$(docker inspect -f '{{.State.Running}}' scinote_web 2>/dev/null)
    db_running=$(docker inspect -f '{{.State.Running}}' scinote_db 2>/dev/null)

    if [ "$web_running" != "true" ] || [ "$db_running" != "true" ]; then
        echo "SciNote containers not fully running (web=${web_running}, db=${db_running}), restarting..."
        cd /home/ga/scinote-web
        docker compose -f docker-compose.production.yml up -d 2>/dev/null || true
        sleep 10
    fi
}

wait_for_scinote_ready() {
    local timeout="${1:-120}"
    local elapsed=0
    echo "Checking SciNote web interface readiness..."

    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${SCINOTE_URL}" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            echo "SciNote is ready (HTTP ${HTTP_CODE}, ${elapsed}s)"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))

        # At 30s mark, check if containers need restart
        if [ $elapsed -eq 30 ] && [ "$HTTP_CODE" = "000" ]; then
            echo "SciNote not responding at 30s, checking containers..."
            ensure_docker_healthy
        fi
    done
    echo "WARNING: SciNote not ready after ${timeout}s (last HTTP code: ${HTTP_CODE})"
    return 1
}

# ============================================================
# Firefox management
# ============================================================

ensure_firefox_running() {
    local url="${1:-${SCINOTE_URL}}"

    # First, ensure SciNote is actually accessible
    ensure_docker_healthy
    wait_for_scinote_ready 90

    if ! pgrep -f firefox > /dev/null; then
        su - ga -c "DISPLAY=:1 firefox '${url}' > /tmp/firefox_task.log 2>&1 &"
        sleep 5
    fi

    local wid
    wid=$(get_firefox_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
    fi
}

# ============================================================
# User assignment helpers (ensure SQL-inserted data is visible in UI)
# ============================================================

get_owner_role_id() {
    scinote_db_query "SELECT id FROM user_roles WHERE name='Owner' AND predefined=true LIMIT 1;" | tr -d '[:space:]'
}

ensure_user_assignment() {
    local assignable_type="$1"
    local assignable_id="$2"
    local user_id="${3:-1}"
    local team_id="${4:-1}"

    [ -z "$assignable_id" ] && return 1

    local role_id
    role_id=$(get_owner_role_id)
    [ -z "$role_id" ] && role_id=1

    local exists
    exists=$(scinote_db_query "SELECT COUNT(*) FROM user_assignments WHERE assignable_type='${assignable_type}' AND assignable_id=${assignable_id} AND user_id=${user_id};" | tr -d '[:space:]')
    if [ "${exists:-0}" = "0" ]; then
        scinote_db_query "INSERT INTO user_assignments (assignable_type, assignable_id, user_id, user_role_id, assigned, team_id, created_at, updated_at) VALUES ('${assignable_type}', ${assignable_id}, ${user_id}, ${role_id}, 0, ${team_id}, NOW(), NOW());"
        echo "Created user_assignment for ${assignable_type}#${assignable_id} -> user#${user_id}"
    fi
}

# ============================================================
# JSON safe string escaping
# ============================================================

json_escape() {
    local str="$1"
    echo "$str" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g'
}

# ============================================================
# Permission-safe file writing
# ============================================================

safe_write_json() {
    local final_path="$1"
    local content="$2"
    local temp_file
    temp_file=$(mktemp /tmp/result.XXXXXX.json)

    echo "$content" > "$temp_file"

    rm -f "$final_path" 2>/dev/null || sudo rm -f "$final_path" 2>/dev/null || true
    cp "$temp_file" "$final_path" 2>/dev/null || sudo cp "$temp_file" "$final_path"
    chmod 666 "$final_path" 2>/dev/null || sudo chmod 666 "$final_path" 2>/dev/null || true
    rm -f "$temp_file"
}
