#!/bin/bash
# Shared utilities for ArkCase tasks

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# ── Ensure K3s and ArkCase services are running ──────────────────────────────
# Critical when loading from QEMU checkpoint — K3s and pods may not be running.
ensure_arkcase_running() {
    # Restore iptables FORWARD policy (K3s/flannel sets it to DROP,
    # which breaks QEMU's SSH port forwarding on checkpoint restore)
    iptables -P FORWARD ACCEPT 2>/dev/null || sudo iptables -P FORWARD ACCEPT 2>/dev/null || true

    # Ensure swap is active
    swapon /swapfile 2>/dev/null || sudo swapon /swapfile 2>/dev/null || true

    # Check if K3s is running
    if ! systemctl is-active k3s >/dev/null 2>&1; then
        echo "Starting K3s..."
        sudo systemctl start k3s
        sleep 10
        # Restore FORWARD after K3s restarts
        sudo iptables -P FORWARD ACCEPT 2>/dev/null || true
    fi

    # Wait for K3s node to be ready
    local elapsed=0
    while [ "$elapsed" -lt 120 ]; do
        if k3s kubectl get nodes --no-headers 2>/dev/null | grep -q "Ready"; then
            echo "K3s node ready after ${elapsed}s"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    # Wait for arkcase-core pod to be running
    elapsed=0
    while [ "$elapsed" -lt 300 ]; do
        local pod_status
        pod_status=$(k3s kubectl get pod arkcase-core-0 -n "$ARKCASE_NS" --no-headers 2>/dev/null | awk '{print $3}')
        if [ "$pod_status" = "Running" ]; then
            echo "arkcase-core-0 is Running after ${elapsed}s"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        if [ $((elapsed % 60)) -eq 0 ]; then
            echo "  Still waiting for arkcase-core-0... ${elapsed}s (status: $pod_status)"
        fi
    done
}

# Auto-start services when task_utils.sh is sourced
ensure_arkcase_running
# IMPORTANT: Port 9443 is used (not 8443) because kubectl port-forward to svc/core
# returns 503 due to haproxy. We use pod/arkcase-core-0 direct on port 9443 via tmux.
ARKCASE_URL="https://localhost:9443/arkcase"
# Admin credentials: password was reset via samba-tool after Helm deploy
# LDAP domain is dev.arkcase.com, so username must be email format
ARKCASE_ADMIN="arkcase-admin@dev.arkcase.com"
ARKCASE_PASS='ArkCase1234!'
ARKCASE_NS="arkcase"

# ── Screenshot ────────────────────────────────────────────────────────────────
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$path" 2>/dev/null || true
}

# ── Ensure Firefox is open on ArkCase ─────────────────────────────────────────
ensure_firefox_on_arkcase() {
    local url="${1:-${ARKCASE_URL}/}"
    # Firefox snap profile location (discovered at runtime)
    local SNAP_PROFILE
    SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")

    # Check if Firefox is already running
    if ! pgrep -f firefox > /dev/null 2>&1; then
        echo "Starting Firefox..."
        if [ -n "$SNAP_PROFILE" ]; then
            su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority firefox -profile '$SNAP_PROFILE' '$url' &" &
        else
            su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority firefox '$url' &" &
        fi
        sleep 15
    else
        # Navigate to URL
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Mozilla Firefox" windowactivate --sync 2>/dev/null || true
        sleep 0.5
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+l
        sleep 0.5
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers "$url"
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return
        sleep 8
    fi
}

# ── Handle SSL warning page ───────────────────────────────────────────────────
handle_ssl_warning() {
    sleep 3
    take_screenshot /tmp/ssl_check.png

    # Check for SSL warning by window title
    local HAS_WARNING=false
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Warning: Potential" 2>/dev/null | grep -q .; then
        HAS_WARNING=true
    fi
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Did Not Connect" 2>/dev/null | grep -q .; then
        HAS_WARNING=true
    fi
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Secure Connection Failed" 2>/dev/null | grep -q .; then
        HAS_WARNING=true
    fi

    if [ "$HAS_WARNING" = true ]; then
        echo "SSL warning detected, accepting risk..."
        for _attempt in 1 2 3; do
            # Click "Advanced..." button (Tab to reach it, then Enter)
            su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Tab Tab Tab Return" 2>/dev/null || true
            sleep 2
            # Click "Accept the Risk and Continue" button
            su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Tab Return" 2>/dev/null || true
            sleep 3
            # Check if we're past the warning
            if ! DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Warning: Potential" 2>/dev/null | grep -q .; then
                echo "SSL warning accepted (attempt $_attempt)"
                break
            fi
        done
    else
        echo "No SSL warning detected"
    fi
}

# ── Wait for ArkCase to be accessible ─────────────────────────────────────────
# NOTE: ArkCase returns 302 redirect to /home.html; use -L to follow and check status
wait_for_arkcase() {
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local http_code
        http_code=$(curl -skL --max-time 10 -o /dev/null -w "%{http_code}" "${ARKCASE_URL}/" 2>/dev/null)
        if [ "$http_code" = "200" ] || [ "$http_code" = "302" ]; then
            echo "ArkCase is accessible (HTTP $http_code)"
            return 0
        fi
        echo "  Waiting for ArkCase... ($elapsed/${timeout}s) [HTTP $http_code]"
        sleep 10
        elapsed=$((elapsed + 10))
    done
    echo "WARNING: ArkCase not responding, continuing anyway"
    return 0
}

# ── Ensure port-forward is active ─────────────────────────────────────────────
# IMPORTANT: Must use pod/arkcase-core-0 not svc/core (haproxy causes 503 via svc)
# Must run as root with system KUBECONFIG, via tmux for persistence
# The tmux session runs a loop so it auto-restarts if the port-forward dies
ensure_portforward() {
    local http_code
    http_code=$(curl -sk --max-time 5 -o /dev/null -w "%{http_code}" "${ARKCASE_URL}/" 2>/dev/null)
    if [ "$http_code" != "302" ] && [ "$http_code" != "200" ]; then
        echo "Restarting port-forward on port 9443... (was HTTP $http_code)"
        pkill -f "kubectl port-forward" 2>/dev/null || true
        sleep 1
        tmux kill-session -t arkcase 2>/dev/null || true
        sleep 1
        # Use a loop in tmux so port-forward auto-restarts on connection drop
        KUBECONFIG=/etc/rancher/k3s/k3s.yaml tmux new-session -d -s arkcase \
            "while true; do KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl port-forward -n arkcase pod/arkcase-core-0 9443:8443 --address 0.0.0.0 2>&1; sleep 2; done"
        sleep 8
        http_code=$(curl -sk --max-time 5 -o /dev/null -w "%{http_code}" "${ARKCASE_URL}/" 2>/dev/null)
        echo "Port-forward restarted, HTTP: $http_code"
    fi
}

# ── ArkCase REST API call ──────────────────────────────────────────────────────
arkcase_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    curl -sk -X "$method" \
        -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        ${data:+-d "$data"} \
        "${ARKCASE_URL}/api/v1/${endpoint}" 2>/dev/null
}

# ── Create a FOIA case via REST API ───────────────────────────────────────────
# NOTE: ArkCase uses "complaintTitle" (not "title") for case name
create_foia_case() {
    local title="$1"
    local details="$2"
    local priority="${3:-Medium}"

    local payload=$(cat <<EOF
{
    "caseType": "GENERAL",
    "complaintTitle": "$title",
    "details": "$details",
    "priority": "$priority",
    "status": "ACTIVE"
}
EOF
)
    arkcase_api POST "plugin/complaint" "$payload" 2>/dev/null || true
}

# ── Auto-login to ArkCase and navigate to a module ────────────────────────────
# Usage: auto_login_arkcase [destination_url]
# Logs in as admin and navigates to destination URL.
# Assumes Firefox snap profile already has SSL cert exception stored.
# Firefox must already be launched before calling this function.
# Default destination: ArkCase dashboard
auto_login_arkcase() {
    local dest="${1:-${ARKCASE_URL}/home.html}"

    echo "Auto-logging in to ArkCase..."

    # Focus and maximize Firefox (already launched by caller)
    focus_firefox
    maximize_firefox
    sleep 2

    # Log in using coordinate-based clicks (1920x1080 resolution)
    # Username field: (994, 312), Password: (994, 368), Log In: (994, 438)
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 994 312 click 1
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers --delay 50 "${ARKCASE_ADMIN}"
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 994 368 click 1
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers --delay 50 "${ARKCASE_PASS}"
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 994 438 click 1
    sleep 12

    # Navigate to destination module
    if [ -n "$dest" ] && [ "$dest" != "${ARKCASE_URL}/home.html" ]; then
        echo "Navigating to: $dest"
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+l
        sleep 0.5
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers "$dest"
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return
        sleep 6
    fi

    echo "Login complete, at: $dest"
}

# ── Navigate Firefox to a URL ──────────────────────────────────────────────────
navigate_to() {
    local url="$1"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+l"
    sleep 0.3
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers '$url'"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return"
    sleep 3
}

# ── Focus Firefox window ───────────────────────────────────────────────────────
focus_firefox() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a "Mozilla Firefox" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a "ArkCase" 2>/dev/null || true
    sleep 0.5
}

# ── Maximize Firefox window ────────────────────────────────────────────────────
maximize_firefox() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 0.5
}
