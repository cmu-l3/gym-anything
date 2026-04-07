#!/bin/bash
echo "=== Exporting build_system_healthcheck result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

SCRIPT_PATH="/usr/local/bin/socioboard-health.sh"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ==============================================================================
# DYNAMIC MUTATION TESTING (ANTI-GAMING)
# We test the script in 3 different states to prove it genuinely checks status.
# ==============================================================================

# 1. Test in Healthy State
log "Running script in healthy state..."
timeout 10 $SCRIPT_PATH > /tmp/out_healthy.raw 2>/dev/null || echo '{"error": "execution failed or timed out"}' > /tmp/out_healthy.raw

# 2. Mutate 1: Stop Apache
log "Stopping apache2 for dynamic test..."
sudo systemctl stop apache2
sleep 2
timeout 10 $SCRIPT_PATH > /tmp/out_no_apache.raw 2>/dev/null || echo '{"error": "execution failed or timed out"}' > /tmp/out_no_apache.raw

# 3. Mutate 2: Start Apache, Stop MariaDB
log "Starting apache2, stopping mariadb for dynamic test..."
sudo systemctl start apache2
sudo systemctl stop mariadb
sleep 2
timeout 15 $SCRIPT_PATH > /tmp/out_no_db.raw 2>/dev/null || echo '{"error": "execution failed or timed out"}' > /tmp/out_no_db.raw

# Restore the environment
log "Restoring system state..."
sudo systemctl start mariadb

# ==============================================================================
# BUNDLE RESULTS INTO JSON
# ==============================================================================
python3 << EOF
import json
import os

script_path = "$SCRIPT_PATH"
task_start = int("$TASK_START")

def read_output(path):
    try:
        with open(path, 'r') as f:
            return f.read().strip()
    except Exception:
        return ""

is_file = os.path.isfile(script_path)
is_executable = os.access(script_path, os.X_OK) if is_file else False
mtime = os.path.getmtime(script_path) if is_file else 0

result = {
    "task_start": task_start,
    "script_exists": is_file,
    "is_executable": is_executable,
    "mtime": mtime,
    "out_healthy": read_output("/tmp/out_healthy.raw"),
    "out_no_apache": read_output("/tmp/out_no_apache.raw"),
    "out_no_db": read_output("/tmp/out_no_db.raw")
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

# Ensure verifier can read it
chmod 666 /tmp/task_result.json

echo "Export complete. Payload saved to /tmp/task_result.json"
cat /tmp/task_result.json