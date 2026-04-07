#!/bin/bash
# Shared utilities for Nx Witness VMS environment tasks

NX_BASE="https://localhost:7001"
NX_ADMIN_PASS="Admin1234!"
NX_TOKEN_FILE="/home/ga/nx_token.txt"

# ============================================================
# Server Readiness
# ============================================================

wait_for_nx_server() {
    local timeout=120
    local elapsed=0
    echo "Waiting for Nx Witness server to start..."
    while [ $elapsed -lt $timeout ]; do
        if curl -sk "${NX_BASE}/rest/v1/system/info" --max-time 5 | grep -q '"version"'; then
            echo "Nx Witness server is up after ${elapsed}s"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "ERROR: Nx Witness server did not start within ${timeout}s"
    return 1
}

# ============================================================
# Authentication / Token Management
# ============================================================

refresh_nx_token() {
    local token
    token=$(curl -sk -X POST "${NX_BASE}/rest/v1/login/sessions" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"admin\", \"password\": \"${NX_ADMIN_PASS}\"}" \
        --max-time 15 | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null || echo "")
    echo "$token" > "$NX_TOKEN_FILE"
    echo "$token"
}

get_nx_token() {
    local token
    token=$(cat "$NX_TOKEN_FILE" 2>/dev/null || echo "")
    if [ -z "$token" ]; then
        token=$(refresh_nx_token)
    fi
    echo "$token"
}

# ============================================================
# API Calls
# ============================================================

nx_api_get() {
    local endpoint="$1"
    local token
    token=$(get_nx_token)
    curl -sk -H "Authorization: Bearer $token" \
        "${NX_BASE}${endpoint}" --max-time 30
}

nx_api_post() {
    local endpoint="$1"
    local data="$2"
    local token
    token=$(get_nx_token)
    curl -sk -X POST "${NX_BASE}${endpoint}" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$data" --max-time 30
}

nx_api_patch() {
    local endpoint="$1"
    local data="$2"
    local token
    token=$(get_nx_token)
    curl -sk -X PATCH "${NX_BASE}${endpoint}" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$data" --max-time 30
}

nx_api_delete() {
    local endpoint="$1"
    local token
    token=$(get_nx_token)
    curl -sk -X DELETE "${NX_BASE}${endpoint}" \
        -H "Authorization: Bearer $token" \
        --max-time 30
}

# ============================================================
# Device/Camera Helpers
# ============================================================

get_all_cameras() {
    nx_api_get "/rest/v1/devices"
}

get_camera_by_name() {
    local name="$1"
    nx_api_get "/rest/v1/devices" | python3 -c "
import sys, json
name = '$name'
try:
    devices = json.load(sys.stdin)
    for d in devices:
        if d.get('name','').lower() == name.lower():
            print(json.dumps(d))
            break
except:
    pass
" 2>/dev/null
}

get_camera_id_by_name() {
    local name="$1"
    get_camera_by_name "$name" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('id',''))
except:
    pass
" 2>/dev/null
}

get_first_camera_id() {
    nx_api_get "/rest/v1/devices" | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    if devices and len(devices) > 0:
        print(devices[0].get('id',''))
except:
    pass
" 2>/dev/null
}

count_cameras() {
    nx_api_get "/rest/v1/devices" | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    print(len(devices) if isinstance(devices, list) else 0)
except:
    print(0)
" 2>/dev/null
}

# ============================================================
# User Helpers
# ============================================================

get_all_users() {
    nx_api_get "/rest/v1/users"
}

count_users() {
    nx_api_get "/rest/v1/users" | python3 -c "
import sys, json
try:
    users = json.load(sys.stdin)
    print(len(users) if isinstance(users, list) else 0)
except:
    print(0)
" 2>/dev/null
}

get_user_by_name() {
    local name="$1"
    nx_api_get "/rest/v1/users" | python3 -c "
import sys, json
name = '$name'
try:
    users = json.load(sys.stdin)
    for u in users:
        if u.get('name','').lower() == name.lower():
            print(json.dumps(u))
            break
except:
    pass
" 2>/dev/null
}

# ============================================================
# Layout Helpers
# ============================================================

get_all_layouts() {
    nx_api_get "/rest/v1/layouts"
}

count_layouts() {
    nx_api_get "/rest/v1/layouts" | python3 -c "
import sys, json
try:
    layouts = json.load(sys.stdin)
    print(len(layouts) if isinstance(layouts, list) else 0)
except:
    print(0)
" 2>/dev/null
}

get_layout_by_name() {
    local name="$1"
    nx_api_get "/rest/v1/layouts" | python3 -c "
import sys, json
name = '$name'
try:
    layouts = json.load(sys.stdin)
    for l in layouts:
        if l.get('name','').lower() == name.lower():
            print(json.dumps(l))
            break
except:
    pass
" 2>/dev/null
}

# ============================================================
# System Helpers
# ============================================================

get_system_info() {
    nx_api_get "/rest/v1/system/info"
}

get_servers() {
    nx_api_get "/rest/v1/servers"
}

get_server_id() {
    nx_api_get "/rest/v1/servers" | python3 -c "
import sys, json
try:
    servers = json.load(sys.stdin)
    if servers and len(servers) > 0:
        print(servers[0].get('id',''))
except:
    pass
" 2>/dev/null
}

# ============================================================
# Firefox / Window Management
# ============================================================

ensure_firefox_running() {
    local url="${1:-https://localhost:7001/static/index.html}"
    if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        echo "Starting Firefox..."
        su - ga -c "DISPLAY=:1 firefox '${url}' &" &
        sleep 8
    else
        echo "Firefox is already running, navigating to URL..."
        navigate_firefox "$url"
    fi
}

navigate_firefox() {
    local url="$1"
    # Focus Firefox window using wmctrl (most reliable)
    DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || \
    DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
    sleep 0.5
    # Open address bar with ctrl+l and type URL
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "$url" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 4
}

maximize_firefox() {
    DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || \
    DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    echo "$path"
}

# ============================================================
# SSL Warning Dismissal (Nx Witness uses self-signed cert)
# ============================================================

dismiss_ssl_warning() {
    # The NX Witness self-signed cert has SAN=<server-uuid>, not localhost,
    # so Firefox always shows the SSL warning. We dismiss it reliably using
    # keyboard navigation: click page body for focus, then Shift+Tab focuses
    # the "Accept the Risk and Continue" button (last tabbable element), Enter clicks it.
    sleep 2
    # Click page body to ensure focus is on page content (not address bar)
    DISPLAY=:1 xdotool mousemove 960 400 click 1 2>/dev/null || true
    sleep 0.5
    # Shift+Tab focuses "Accept the Risk and Continue" (last focusable element)
    DISPLAY=:1 xdotool key shift+Tab 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    # If it didn't work (Advanced section wasn't expanded), try expanding first
    # then repeating
    DISPLAY=:1 xdotool mousemove 960 400 click 1 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key shift+Tab 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 3
}

# ============================================================
# Recording Schedule Helper
# ============================================================

enable_recording_for_camera() {
    local camera_id="$1"
    local fps="${2:-15}"

    nx_api_patch "/rest/v1/devices/${camera_id}" "{
        \"schedule\": {
            \"isEnabled\": true,
            \"tasks\": [
                {
                    \"dayOfWeek\": 1,
                    \"startTime\": 0,
                    \"endTime\": 86400,
                    \"recordingType\": \"always\",
                    \"streamQuality\": \"high\",
                    \"fps\": ${fps},
                    \"bitrateKbps\": 2048
                },
                {
                    \"dayOfWeek\": 2,
                    \"startTime\": 0,
                    \"endTime\": 86400,
                    \"recordingType\": \"always\",
                    \"streamQuality\": \"high\",
                    \"fps\": ${fps},
                    \"bitrateKbps\": 2048
                },
                {
                    \"dayOfWeek\": 3,
                    \"startTime\": 0,
                    \"endTime\": 86400,
                    \"recordingType\": \"always\",
                    \"streamQuality\": \"high\",
                    \"fps\": ${fps},
                    \"bitrateKbps\": 2048
                },
                {
                    \"dayOfWeek\": 4,
                    \"startTime\": 0,
                    \"endTime\": 86400,
                    \"recordingType\": \"always\",
                    \"streamQuality\": \"high\",
                    \"fps\": ${fps},
                    \"bitrateKbps\": 2048
                },
                {
                    \"dayOfWeek\": 5,
                    \"startTime\": 0,
                    \"endTime\": 86400,
                    \"recordingType\": \"always\",
                    \"streamQuality\": \"high\",
                    \"fps\": ${fps},
                    \"bitrateKbps\": 2048
                },
                {
                    \"dayOfWeek\": 6,
                    \"startTime\": 0,
                    \"endTime\": 86400,
                    \"recordingType\": \"always\",
                    \"streamQuality\": \"high\",
                    \"fps\": ${fps},
                    \"bitrateKbps\": 2048
                },
                {
                    \"dayOfWeek\": 7,
                    \"startTime\": 0,
                    \"endTime\": 86400,
                    \"recordingType\": \"always\",
                    \"streamQuality\": \"high\",
                    \"fps\": ${fps},
                    \"bitrateKbps\": 2048
                }
            ]
        }
    }"
}
