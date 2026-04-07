#!/bin/bash
echo "=== Setting up Configure DB Backup task ==="

# Source shared utilities
# Do NOT use set -euo pipefail (cross-cutting pattern #25)
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Record initial state of ELA config directory for diff
echo "Recording initial config state..."
find /opt/ManageEngine/EventLog/conf/ -type f -exec md5sum {} \; 2>/dev/null | sort > /tmp/ela_conf_initial.md5

# Record initial DB state (backup related keys)
echo "Recording initial DB state..."
ela_db_query "SELECT * FROM systemconfig WHERE config_key ILIKE '%backup%'" > /tmp/ela_backup_config_initial.txt 2>/dev/null || echo "NO_DB_ACCESS" > /tmp/ela_backup_config_initial.txt

# Clean up any previous task artifacts
rm -f /home/ga/backup_config_done.txt
rm -rf /opt/ManageEngine/EventLog/backup 2>/dev/null || true

# Wait for EventLog Analyzer to be ready
wait_for_eventlog_analyzer 900

# Ensure Firefox is open on the ELA main page
# We start at the dashboard; agent must find the settings
ensure_firefox_on_ela "/event/index.do"

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="