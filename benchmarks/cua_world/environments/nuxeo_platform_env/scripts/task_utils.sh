#!/bin/bash
# Shared utilities for Nuxeo Platform task setup scripts.
# Source this file from each setup_task.sh:
#   source /workspace/scripts/task_utils.sh

NUXEO_URL="http://localhost:8080/nuxeo"
NUXEO_ADMIN="Administrator"
NUXEO_PASS="Administrator"
NUXEO_AUTH="$NUXEO_ADMIN:$NUXEO_PASS"

# Nuxeo Web UI base URL for browser navigation
NUXEO_UI="http://localhost:8080/nuxeo/ui"

# ---------------------------------------------------------------------------
# Run an X11 command as the 'ga' user with the correct display environment.
# All wmctrl, xdotool, etc. must run as 'ga' (not root) to manipulate ga's
# Firefox window.
# Usage: ga_x "xdotool key Escape"
# ---------------------------------------------------------------------------
ga_x() {
    sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority $*" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Wait for Nuxeo HTTP endpoint to respond (200/302)
# ---------------------------------------------------------------------------
wait_for_nuxeo() {
    local timeout=${1:-180}
    local elapsed=0
    echo "Waiting for Nuxeo to be ready..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            "$NUXEO_URL/login.jsp" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
            echo "Nuxeo is ready (HTTP $HTTP_CODE) after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        [ $((elapsed % 30)) -eq 0 ] && echo "  Still waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done
    echo "WARNING: Nuxeo did not become ready within ${timeout}s"
    return 1
}

# ---------------------------------------------------------------------------
# Execute a Nuxeo REST API call and return the response
# ---------------------------------------------------------------------------
nuxeo_api() {
    local method="$1"
    local path="$2"
    local data="${3:-}"
    if [ -n "$data" ]; then
        curl -s -u "$NUXEO_AUTH" \
            -H "Content-Type: application/json" \
            -H "X-NXproperties: *" \
            -X "$method" \
            "$NUXEO_URL/api/v1$path" \
            -d "$data"
    else
        curl -s -u "$NUXEO_AUTH" \
            -H "Content-Type: application/json" \
            -H "X-NXproperties: *" \
            -X "$method" \
            "$NUXEO_URL/api/v1$path"
    fi
}

# ---------------------------------------------------------------------------
# Check if a document exists at the given path (e.g. /default-domain/workspaces/Projects)
# ---------------------------------------------------------------------------
doc_exists() {
    local path="$1"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
        "$NUXEO_URL/api/v1/path$path")
    [ "$code" = "200" ]
}

# ---------------------------------------------------------------------------
# Create a document via the REST API if it does not already exist.
# $1 = parent_path  (e.g. /default-domain/workspaces)
# $2 = type         (e.g. Workspace, File, Note)
# $3 = name         (the path component / short name)
# $4 = title        (dc:title)
# $5 = description  (optional dc:description, default empty)
# ---------------------------------------------------------------------------
create_doc_if_missing() {
    local parent_path="$1"
    local type="$2"
    local name="$3"
    local title="$4"
    local desc="${5:-}"

    local full_path="$parent_path/$name"
    if doc_exists "$full_path"; then
        echo "Document already exists: $full_path"
        return 0
    fi

    local payload
    payload=$(cat <<EOFJSON
{
  "entity-type": "document",
  "type": "$type",
  "name": "$name",
  "properties": {
    "dc:title": "$title",
    "dc:description": "$desc"
  }
}
EOFJSON
)
    local result
    result=$(nuxeo_api POST "/path$parent_path/" "$payload")
    echo "Created $type '$name': $(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid','done'))" 2>/dev/null || echo 'done')"
}

# ---------------------------------------------------------------------------
# Kill Firefox and restart with a given URL.
# Uses sudo -u ga with DBUS_SESSION_BUS_ADDRESS (required for snap Firefox).
# $1 = URL to open
# $2 = seconds to wait for Firefox window (default 8)
# ---------------------------------------------------------------------------
open_nuxeo_url() {
    local url="$1"
    local wait_sec="${2:-8}"

    echo "Restarting Firefox with URL: $url"

    # Kill any existing Firefox
    pkill -9 -f firefox 2>/dev/null || true
    sleep 2

    # Launch snap Firefox as 'ga' user with DBUS session (required for snap confinement)
    sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus' \
        firefox '$url' > /tmp/firefox_nuxeo.log 2>&1 &"

    sleep "$wait_sec"

    # Maximize Firefox window — must run as 'ga' to manipulate ga's X windows
    for i in $(seq 1 20); do
        WID=$(ga_x "wmctrl -l" | grep -i "firefox\|mozilla\|nuxeo" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            ga_x "wmctrl -ia '$WID'"
            ga_x "wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz"
            echo "Firefox window maximized (WID=$WID)"
            break
        fi
        sleep 1
    done
}

# ---------------------------------------------------------------------------
# Automate login to Nuxeo Web UI (Administrator / Administrator).
# Assumes Firefox is already open on login.jsp and the window is maximized.
# All X11 commands run as 'ga' (not root) to interact with ga's display.
# ---------------------------------------------------------------------------
nuxeo_login() {
    echo "Automating Nuxeo login..."
    sleep 5  # Wait for login page to fully render

    # Dismiss any dialog (e.g. password save popup) with Escape
    ga_x "xdotool key Escape"
    sleep 0.5

    # Ensure Firefox window is maximized and focused (must run as ga)
    local WID
    WID=$(ga_x "wmctrl -l" | grep -i "firefox\|mozilla\|nuxeo" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        ga_x "wmctrl -ia '$WID'"
        ga_x "wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz"
        sleep 1
    fi

    # Navigate to login.jsp to ensure we're on the login form
    ga_x "xdotool key ctrl+l"
    sleep 0.5
    ga_x "xdotool type --clearmodifiers 'http://localhost:8080/nuxeo/login.jsp'"
    sleep 0.3
    ga_x "xdotool key Return"
    sleep 5

    # Dismiss password save dialog if present
    ga_x "xdotool key Escape"
    sleep 0.5

    # Click username field.
    # In a maximized Firefox window on 1920x1080, the Nuxeo login form is
    # positioned with its center at approximately x=600, y=564.
    ga_x "xdotool mousemove --sync 600 564 click 1"
    sleep 0.5
    ga_x "xdotool key ctrl+a"
    ga_x "xdotool type --clearmodifiers --delay 50 '$NUXEO_ADMIN'"
    sleep 0.3

    # Tab to the password field (below username)
    ga_x "xdotool key Tab"
    sleep 0.3
    ga_x "xdotool key ctrl+a"
    ga_x "xdotool type --clearmodifiers --delay 50 '$NUXEO_PASS'"
    sleep 0.3

    # Submit the form
    ga_x "xdotool key Return"

    sleep 8  # Wait for login + redirect to home

    # Dismiss password save dialog that appears after successful login
    ga_x "xdotool key Escape"
    sleep 0.5

    echo "Login submitted."
}

# ---------------------------------------------------------------------------
# Navigate to a Nuxeo Web UI URL in already-open Firefox (using address bar).
# ---------------------------------------------------------------------------
navigate_to() {
    local url="$1"
    echo "Navigating to: $url"
    ga_x "xdotool key ctrl+l"
    sleep 0.5
    ga_x "xdotool type --clearmodifiers '$url'"
    sleep 0.3
    ga_x "xdotool key Return"
    sleep 5
}
