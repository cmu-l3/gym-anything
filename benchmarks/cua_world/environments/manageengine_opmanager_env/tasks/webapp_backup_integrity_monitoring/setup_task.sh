#!/bin/bash
# setup_task.sh — Web Application Backup Integrity Monitoring
# Waits for OpManager, creates dummy backup files to pass OpManager's pre-flight checks,
# and writes the monitoring specification to the desktop.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up WebApp Backup Integrity Monitoring Task ==="

# ------------------------------------------------------------
# 1. Wait for OpManager to be ready
# ------------------------------------------------------------
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
# 2. Create actual files so OpManager doesn't throw "File not found" errors
# ------------------------------------------------------------
echo "[setup] Creating target file structure..."
mkdir -p /var/backups/webapp
truncate -s 10M /var/backups/webapp/daily_archive.tar.gz
# Ensure the files are readable by the system processes
chmod -R 755 /var/backups
echo "[setup] Dummy backup files created at /var/backups/webapp/"

# ------------------------------------------------------------
# 3. Write monitoring spec file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/backup_monitor_spec.txt" << 'SPEC_EOF'
WEB APPLICATION BACKUP INTEGRITY MONITORING
=============================================
Target Device: localhost (127.0.0.1)

Please configure the following monitors on the local OpManager server
to ensure our nightly backups are completing successfully and not
overwhelming local storage.

1. FOLDER MONITOR (Storage Consumption Check)
---------------------------------------------
We need to ensure the backup directory doesn't consume too much disk space.
- Directory Path: /var/backups/webapp
- Alert Condition: Trigger an alert (Warning or Critical) if the folder size is GREATER THAN 10000 MB.

2. FILE MONITOR (Backup Integrity Check)
---------------------------------------------
We need to ensure the nightly tarball is not suspiciously small (which indicates a failed backup job).
- File Path: /var/backups/webapp/daily_archive.tar.gz
- Alert Condition: Trigger an alert (Warning or Critical) if the file size is LESS THAN 500 MB.

Instructions:
Log in to OpManager, go to the Inventory, click on the 'localhost' (or 127.0.0.1) device, navigate to the Monitors tab, and add the appropriate File and Folder monitors.
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/backup_monitor_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Spec file written to $DESKTOP_DIR/backup_monitor_spec.txt"

# ------------------------------------------------------------
# 4. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/backup_monitor_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded: $(cat /tmp/backup_monitor_task_start.txt)"

# ------------------------------------------------------------
# 5. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 6. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/backup_monitor_setup_screenshot.png" || true

echo "[setup] === Setup Complete ==="