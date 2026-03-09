#!/bin/bash
# task_utils.sh - Shared utilities for Aerobridge environment tasks
# Source this file in task setup/export scripts:
#   source /workspace/scripts/task_utils.sh

AEROBRIDGE_DIR="/opt/aerobridge"
AEROBRIDGE_VENV="/opt/aerobridge_venv"
AEROBRIDGE_URL="http://localhost:8000"
AEROBRIDGE_ADMIN_URL="http://localhost:8000/admin/"
AEROBRIDGE_DB="${AEROBRIDGE_DIR}/aerobridge.sqlite3"

# ============================================================
# Django query helper — runs a Python snippet using Django ORM
# Usage: django_query "from registry.models import X; print(X.objects.count())"
# ============================================================
django_query() {
    local code="$1"
    cd "${AEROBRIDGE_DIR}"
    set -a
    source "${AEROBRIDGE_DIR}/.env" 2>/dev/null || true
    set +a
    "${AEROBRIDGE_VENV}/bin/python3" -c "
import os, sys, django
sys.path.insert(0, '${AEROBRIDGE_DIR}')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
with open('${AEROBRIDGE_DIR}/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip(\"'\").strip('\"'))
django.setup()
${code}
" 2>/dev/null
}

# ============================================================
# Wait for Aerobridge server to be ready
# Auto-restarts via systemd if not responding after initial wait
# ============================================================
wait_for_aerobridge() {
    local timeout="${1:-60}"
    local elapsed=0
    local restarted=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            "${AEROBRIDGE_URL}/admin/" --max-time 3 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            return 0
        fi
        # After 15s without response, try restarting the service
        if [ $elapsed -ge 15 ] && [ $restarted -eq 0 ]; then
            echo "Server not responding after 15s, attempting restart..." >&2
            systemctl restart aerobridge 2>/dev/null || \
                setsid bash -c "set -a; source /opt/aerobridge/.env; set +a; \
                    cd /opt/aerobridge; \
                    exec /opt/aerobridge_venv/bin/python manage.py runserver 0.0.0.0:8000 \
                    >> /var/log/aerobridge_server.log 2>&1" &
            restarted=1
            sleep 5
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "WARNING: Aerobridge not ready after ${timeout}s" >&2
    return 1
}

# ============================================================
# Take a screenshot
# ============================================================
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "${path}" 2>/dev/null || \
    DISPLAY=:1 import -window root "${path}" 2>/dev/null || true
    echo "Screenshot saved to: ${path}"
}

# ============================================================
# Ensure Aerobridge server is running (auto-restart via systemd)
# ============================================================
ensure_server_running() {
    # Check if server is responding
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "${AEROBRIDGE_URL}/admin/" --max-time 3 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        return 0
    fi
    echo "Server not responding, attempting restart via systemd..."
    systemctl restart aerobridge 2>/dev/null || \
        setsid bash -c "set -a; source /opt/aerobridge/.env; set +a; cd /opt/aerobridge; \
            exec /opt/aerobridge_venv/bin/python manage.py runserver 0.0.0.0:8000 \
            >> /var/log/aerobridge_server.log 2>&1" &
    sleep 5
}

# ============================================================
# Kill all running Firefox instances
# ============================================================
kill_firefox() {
    pkill -9 -f firefox 2>/dev/null || true
    sleep 2
}

# ============================================================
# Launch Firefox to a specific URL as user 'ga'
# Uses snap profile path which is where Ubuntu snap Firefox stores data
# ============================================================
launch_firefox() {
    local url="${1:-${AEROBRIDGE_ADMIN_URL}}"
    kill_firefox
    # Remove snap lock files (Firefox snap stores profile in snap sandbox)
    rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
           /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock
    su - ga -c "rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
        /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock; \
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance \
        -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile \
        '${url}' &"
    sleep 6
}

# ============================================================
# Record current counts for anti-gaming / task start state
# Usage: record_count "Aircraft" > /tmp/aircraft_count_before
# ============================================================
record_count() {
    local model_import="$1"
    local model_class="$2"
    django_query "
from ${model_import} import ${model_class}
print(${model_class}.objects.count())
" 2>/dev/null || echo "0"
}

# ============================================================
# Record task start time for temporal anti-gaming checks
# ============================================================
record_task_start() {
    date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time
    echo "Task start time recorded: $(cat /tmp/task_start_time)"
}
