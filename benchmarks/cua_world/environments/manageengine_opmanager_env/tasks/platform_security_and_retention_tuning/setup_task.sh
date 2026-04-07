#!/bin/bash
# setup_task.sh — Platform Security and Retention Tuning
# Writes the compliance memo to the desktop and prepares the environment.

source /workspace/scripts/task_utils.sh

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

# ------------------------------------------------------------
# Write compliance memo file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/platform_compliance_memo.txt" << 'MEMO_EOF'
IT Platform Compliance Memorandum
Date: 2024-05-10
To: NOC Administration
Subject: Platform Security and Data Retention Tuning

The Database Administration and Information Security teams have issued new global configuration requirements for the OpManager monitoring platform to ensure stability and compliance.

ACTION REQUIRED:
Please log in to OpManager and update the following settings immediately.

1. Database Maintenance (Pruning)
Navigate to Settings -> Basic Settings -> Database Maintenance (or General Settings -> Database Maintenance) and apply these exact retention periods (in days):
- Detailed Polled Data: 8
- Hourly Polled Data: 35
- Daily Polled Data: 190
- Alarms: 45
- Events: 25
- Syslog / Traps: 12

2. Global Security Settings
Navigate to Settings -> Basic Settings -> System Settings and apply the following:
- Session Expiry Time (Session Timeout): 12 minutes

All changes must be saved. Audit scripts will verify these numerical values in the system database.
MEMO_EOF

chown ga:ga "$DESKTOP_DIR/platform_compliance_memo.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Compliance memo written to $DESKTOP_DIR/platform_compliance_memo.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/platform_tuning_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/platform_tuning_setup_screenshot.png" || true

echo "[setup] platform_security_and_retention_tuning setup complete."