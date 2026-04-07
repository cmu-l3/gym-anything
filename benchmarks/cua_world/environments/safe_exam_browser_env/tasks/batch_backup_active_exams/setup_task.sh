#!/bin/bash
echo "=== Setting up batch_backup_active_exams task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up any artifacts from previous runs
sudo rm -rf /home/ga/Documents/ExamBackups 2>/dev/null || true
sudo rm -f /tmp/task_start_time.txt /tmp/batch_backup_result.json /tmp/ground_truth_exams.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Extract ground truth: Determine which exams are active/inactive directly from the SEB DB
# In SEB Server, 'status' in configuration_node usually maps as: 1/2 = Active/Ready, 0 = Draft, 3 = Archived
docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT name, status FROM configuration_node WHERE type='EXAM_CONFIG'" > /tmp/all_configs.txt || true

python3 << 'PYEOF'
import json

active_names = []
inactive_names = []
try:
    with open('/tmp/all_configs.txt', 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 2:
                name = parts[0]
                status = parts[1].strip()
                # Consider 1 (Ready) and 2 (Active) as active statuses
                if status in ['1', '2', 'ACTIVE', 'READY']:
                    active_names.append(name)
                else:
                    inactive_names.append(name)
except Exception as e:
    print(f"Error parsing DB configs: {e}")

# Fallback if DB query failed (to ensure verifier doesn't crash)
if not active_names and not inactive_names:
    active_names = ["Demo Exam Configuration"]
    inactive_names = []

gt = {
    "active": active_names,
    "inactive": inactive_names
}
with open('/tmp/ground_truth_exams.json', 'w') as f:
    json.dump(gt, f)
print("Ground truth saved:", gt)
PYEOF

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server to put agent in starting position
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot showing logged-in state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="