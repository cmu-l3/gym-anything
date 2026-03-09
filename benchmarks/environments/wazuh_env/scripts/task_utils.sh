#!/bin/bash
# Shared utilities for Wazuh environment tasks

WAZUH_API_URL="https://localhost:55000"
WAZUH_API_USER="wazuh-wui"
WAZUH_API_PASS='MyS3cr37P450r.*-'
WAZUH_INDEXER_URL="https://localhost:9200"
WAZUH_INDEXER_USER="admin"
WAZUH_INDEXER_PASS="SecretPassword"
WAZUH_DASHBOARD_URL="https://localhost"

# Correct navigation URLs (discovered by exploring Wazuh 4.9.2 dashboard)
WAZUH_URL_HOME="https://localhost/app/wz-home"
WAZUH_URL_GROUPS="https://localhost/app/endpoint-groups#/manager/?tab=groups"
WAZUH_URL_RULES="https://localhost/app/rules#/manager/tab=ruleset"
WAZUH_URL_CONFIG="https://localhost/app/settings#/manager/?tab=configuration"
WAZUH_URL_AGENTS="https://localhost/app/endpoints-summary"
WAZUH_URL_SCA="https://localhost/app/configuration-assessment#/overview/?tab=sca&agentId=000"

# Docker Compose v2 names the container: <project>-<service>-<replica>
# Project dir is "wazuh", service is "wazuh.manager" -> container: wazuh-wazuh.manager-1
WAZUH_MANAGER_CONTAINER="wazuh-wazuh.manager-1"

# =====================
# API Authentication
# =====================

# Get JWT token from Wazuh API
get_api_token() {
    curl -sk -u "${WAZUH_API_USER}:${WAZUH_API_PASS}" \
        -X POST "${WAZUH_API_URL}/security/user/authenticate?raw=true"
}

# Make an authenticated Wazuh API call
# Usage: wazuh_api GET /agents
# Usage: wazuh_api POST /groups '{"group_id":"linux-servers"}'
wazuh_api() {
    local method="${1:-GET}"
    local endpoint="${2:-/}"
    local body="${3:-}"
    local token
    token=$(get_api_token)

    if [ -n "$body" ]; then
        curl -sk -X "$method" "${WAZUH_API_URL}${endpoint}" \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            -d "$body"
    else
        curl -sk -X "$method" "${WAZUH_API_URL}${endpoint}" \
            -H "Authorization: Bearer ${token}"
    fi
}

# Query Wazuh Indexer (OpenSearch)
wazuh_indexer_query() {
    local endpoint="${1:-/_cluster/health}"
    local body="${2:-}"
    if [ -n "$body" ]; then
        curl -sk -X POST "${WAZUH_INDEXER_URL}${endpoint}" \
            -u "${WAZUH_INDEXER_USER}:${WAZUH_INDEXER_PASS}" \
            -H "Content-Type: application/json" \
            -d "$body"
    else
        curl -sk "${WAZUH_INDEXER_URL}${endpoint}" \
            -u "${WAZUH_INDEXER_USER}:${WAZUH_INDEXER_PASS}"
    fi
}

# =====================
# Agent Management
# =====================

# List all agents
list_agents() {
    wazuh_api GET "/agents?pretty=true"
}

# Get agent count
get_agent_count() {
    wazuh_api GET "/agents?select=id" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('data', {}).get('total_affected_items', 0))
" 2>/dev/null || echo "0"
}

# Get agent group membership
get_agent_groups() {
    local agent_id="$1"
    wazuh_api GET "/agents/${agent_id}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('affected_items', [])
if items:
    print(json.dumps(items[0].get('group', [])))
" 2>/dev/null || echo "[]"
}

# =====================
# Group Management
# =====================

# Check if an agent group exists
group_exists() {
    local group_name="$1"
    local token
    token=$(get_api_token)
    local result
    result=$(curl -sk -X GET "${WAZUH_API_URL}/groups?search=${group_name}" \
        -H "Authorization: Bearer ${token}")
    echo "$result" | grep -q "\"${group_name}\"" && return 0 || return 1
}

# List all groups
list_groups() {
    wazuh_api GET "/groups?pretty=true"
}

# =====================
# Rules Management
# =====================

# List all rules
list_rules() {
    wazuh_api GET "/rules?pretty=true"
}

# Get rules by level
get_rules_by_level() {
    local level="$1"
    wazuh_api GET "/rules?level=${level}&pretty=true"
}

# Check if a rule with given ID exists
rule_exists() {
    local rule_id="$1"
    local result
    result=$(wazuh_api GET "/rules?rule_ids=${rule_id}")
    echo "$result" | grep -q "\"id\": ${rule_id}" && return 0 || return 1
}

# Get content of a rules file
get_rules_file_content() {
    local filename="${1:-local_rules.xml}"
    wazuh_api GET "/rules/files/${filename}?pretty=true"
}

# Upload/update rules file content
upload_rules_file() {
    local filename="${1:-local_rules.xml}"
    local content_file="$2"
    local token
    token=$(get_api_token)
    curl -sk -X PUT "${WAZUH_API_URL}/rules/files/${filename}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${content_file}"
}

# =====================
# Decoders Management
# =====================

# Get decoder file content
get_decoder_file_content() {
    local filename="${1:-local_decoder.xml}"
    wazuh_api GET "/decoders/files/${filename}?pretty=true"
}

# =====================
# Firefox / Dashboard
# =====================

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Get Firefox window ID
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "mozilla\|firefox" | awk '{print $1}' | head -1
}

# Dismiss Firefox SSL certificate warning via xdotool
# Firefox self-signed cert warning: click "Advanced..." then "Accept the Risk and Continue"
dismiss_ssl_warning() {
    sleep 3
    # Check if SSL warning is on screen by looking for the error page title
    local page_title
    page_title=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
    if echo "$page_title" | grep -qi "warning\|secure\|privacy\|certificate\|risk"; then
        echo "SSL warning detected, dismissing..."
        # Click "Advanced..." button (bottom-left area of error page)
        DISPLAY=:1 xdotool key Tab Tab Tab Tab Return 2>/dev/null || true
        sleep 2
        # Click "Accept the Risk and Continue" link
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 2
    fi

    # Fallback: use xdotool to click Advanced button at known coordinates
    # SSL warning page: Advanced button is around (879,512) in 1280x720 scale -> (1318,768) in 1920x1080
    DISPLAY=:1 xdotool mousemove 1318 768 click 1 2>/dev/null || true
    sleep 2
    # "Accept the Risk" link appears below; click it (roughly y+200)
    DISPLAY=:1 xdotool mousemove 1251 1005 click 1 2>/dev/null || true
    sleep 2
}

# Ensure Firefox is running, focused on Wazuh dashboard, and SSL accepted
ensure_firefox_wazuh() {
    local url="${1:-${WAZUH_DASHBOARD_URL}}"
    local firefox_wid
    firefox_wid=$(get_firefox_window_id)

    FIREFOX_CMD="firefox"
    [ -f /snap/bin/firefox ] && FIREFOX_CMD="/snap/bin/firefox"

    if [ -z "$firefox_wid" ]; then
        echo "Starting Firefox..."
        su - ga -c "DISPLAY=:1 ${FIREFOX_CMD} --new-instance ${url} &" 2>/dev/null || true
        sleep 15
        firefox_wid=$(get_firefox_window_id)
        # Dismiss SSL warning on first load
        dismiss_ssl_warning
        # Wait for dashboard to load after SSL accept
        sleep 8
    fi

    if [ -n "$firefox_wid" ]; then
        DISPLAY=:1 wmctrl -ia "$firefox_wid" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
}

# Navigate Firefox to URL (ensures SSL is accepted first)
navigate_firefox_to() {
    local url="$1"
    ensure_firefox_wazuh
    sleep 1
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "$url"
    sleep 0.3
    DISPLAY=:1 xdotool key Return
    sleep 6
    # Dismiss any SSL warning that appears for this URL
    dismiss_ssl_warning
    sleep 3
}

# Wait for a window title
wait_for_window() {
    local title="$1"
    local timeout="${2:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$title"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# =====================
# Manager Container
# =====================

# Execute command in Wazuh manager container
# Container name per Docker Compose v2: wazuh-wazuh.manager-1
wazuh_exec() {
    docker exec "${WAZUH_MANAGER_CONTAINER}" "$@"
}

# Restart Wazuh manager service
restart_wazuh_manager() {
    wazuh_exec /var/ossec/bin/wazuh-control restart 2>/dev/null || \
        docker restart "${WAZUH_MANAGER_CONTAINER}"
    sleep 20
    echo "Wazuh manager restarted"
}

# =====================
# Verification Helpers
# =====================

# Check if Wazuh API is reachable
check_api_health() {
    curl -sk -u "${WAZUH_API_USER}:${WAZUH_API_PASS}" \
        "${WAZUH_API_URL}/" | grep -q "Wazuh"
}

# Check indexer health
check_indexer_health() {
    curl -sk -u "${WAZUH_INDEXER_USER}:${WAZUH_INDEXER_PASS}" \
        "${WAZUH_INDEXER_URL}/_cluster/health" | grep -qE '"status":"(green|yellow)"'
}

# Write result JSON safely
safe_write_result() {
    local file="$1"
    local content="$2"
    local tmpfile
    tmpfile=$(mktemp /tmp/result.XXXXXX.json)
    echo "$content" > "$tmpfile"
    rm -f "$file" 2>/dev/null || sudo rm -f "$file" 2>/dev/null || true
    cp "$tmpfile" "$file" 2>/dev/null || sudo cp "$tmpfile" "$file"
    chmod 666 "$file" 2>/dev/null || sudo chmod 666 "$file" 2>/dev/null || true
    rm -f "$tmpfile"
}

echo "task_utils.sh loaded"
