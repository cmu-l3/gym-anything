#!/bin/bash
# setup_task.sh — NOC Custom Alarm View Segregation
# Waits for OpManager to be ready, writes the policy document, and records the start state.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up NOC Custom Alarm View Segregation Task ==="

# 1. Wait for OpManager to be ready
echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] WARNING: OpManager not ready after ${WAIT_TIMEOUT}s, continuing anyway." >&2
        break
    fi
done
echo "[setup] OpManager is ready."

# 2. Write Policy Document
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/alarm_view_policy.txt" << 'EOF'
NOC Alarm View Segregation Policy

To reduce alert fatigue, the following Custom Alarm Views must be created in OpManager.

1. Network Team View
   - View Name: Network-Core-Critical
   - Filter by Severity: Critical
   - Filter by Category: Router, Switch

2. SysAdmin Team View
   - View Name: SysAdmin-Infrastructure-Alerts
   - Filter by Severity: Critical, Trouble
   - Filter by Category: Server (or Windows/Linux Server), Storage

Instructions:
1. Log in to OpManager (http://localhost:8060, admin/Admin@123).
2. Go to the Alarms section.
3. Click on the filter/views icon to create a New Custom View.
4. Name the view and apply the specified Severity and Category filters.
5. Save the view. Repeat for the second view.
EOF

chown ga:ga "$DESKTOP_DIR/alarm_view_policy.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Policy document written to ~/Desktop/alarm_view_policy.txt"

# 3. Record task start timestamp
date +%s > /tmp/task_start_time.txt
echo "[setup] Task start time recorded."

# 4. Ensure Firefox is open on OpManager dashboard and capture initial state
ensure_firefox_on_opmanager 3 || true
take_screenshot "/tmp/task_initial.png" || true

echo "[setup] === Setup Complete ==="