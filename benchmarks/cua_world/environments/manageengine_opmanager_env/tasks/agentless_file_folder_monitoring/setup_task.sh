#!/bin/bash
# setup_task.sh — Agentless File and Folder Monitoring Setup
# Creates necessary local directories, writes policy, and prepares OpManager.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Agentless File and Folder Monitoring Task ==="

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
# 2. Create Target Files and Folders (for UI validation)
# ------------------------------------------------------------
echo "[setup] Creating target directories and files on the local filesystem..."
mkdir -p /var/backups/postgres
mkdir -p /var/sftp/uploads
mkdir -p /etc/myapp
touch /etc/myapp/config.json

# Provide some baseline data
echo '{"status": "active", "version": "1.4"}' > /etc/myapp/config.json
for i in {1..5}; do touch "/var/sftp/uploads/data_${i}.dat"; done

# Set correct permissions so OpManager SSH monitoring can read them
chown -R ga:ga /var/backups/postgres /var/sftp/uploads /etc/myapp
chmod 755 /var/backups/postgres /var/sftp/uploads /etc/myapp
chmod 644 /etc/myapp/config.json
echo "[setup] Filesystem targets created."

# ------------------------------------------------------------
# 3. Write Storage Monitoring Policy to Desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/storage_monitoring_policy.txt" << 'POLICY_EOF'
STORAGE AND FILE QUEUE MONITORING POLICY
Document ID: INF-MON-082
Effective Date: 2024-04-10
Team: Data Engineering & SysAdmin

OBJECTIVE:
Configure agentless file and folder monitoring on the local OpManager server 
to track critical backup directories and SFTP processing queues.

REQUIREMENTS:

1. CREDENTIAL PROVISIONING
   Since deep file metrics require shell access, you must create a new CLI / SSH 
   credential profile.
   - Profile Name: Local-System-SSH
   - Protocol: CLI / SSH
   - Username: ga
   - Password: password123
   - Prompt: (leave default or use $/#/>)

2. DEVICE ASSOCIATION
   Ensure the localhost device (127.0.0.1) is in OpManager's device inventory and 
   has the 'Local-System-SSH' credential assigned to it. If it does not exist, 
   add it and associate the credential.

3. FOLDER MONITOR 1: Database Backups
   - Device: 127.0.0.1
   - Monitor Name: DB-Backup-Health
   - Target Folder Path: /var/backups/postgres
   - Alert Condition: Alert when Folder Size exceeds 5000 MB.

4. FOLDER MONITOR 2: SFTP Queue
   - Device: 127.0.0.1
   - Monitor Name: SFTP-Processing-Queue
   - Target Folder Path: /var/sftp/uploads
   - Alert Condition: Alert when File Count exceeds 500.

5. FILE MONITOR: Application Configuration
   - Device: 127.0.0.1
   - Monitor Name: Critical-App-Config
   - Target File Path: /etc/myapp/config.json
   - Alert Condition: Alert on File Modification or if File Does Not Exist.

Note: Target paths exist on the local file system. Ensure absolute paths are used exactly as written.
POLICY_EOF

chown ga:ga "$DESKTOP_DIR/storage_monitoring_policy.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Monitoring policy written to $DESKTOP_DIR/storage_monitoring_policy.txt"

# ------------------------------------------------------------
# 4. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_timestamp.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 5. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 6. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/agentless_setup_screenshot.png" || true

echo "[setup] === Setup Complete ==="