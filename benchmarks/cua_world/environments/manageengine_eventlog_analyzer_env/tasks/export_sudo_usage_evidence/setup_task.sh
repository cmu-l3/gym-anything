#!/bin/bash
echo "=== Setting up Export Sudo Usage Evidence task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# Clean up any previous artifacts
rm -f /home/ga/Documents/sudo_evidence.pdf
rm -f /tmp/sudo_evidence.pdf
mkdir -p /home/ga/Documents

# =====================================================
# Generate Real Log Data
# =====================================================
echo "Generating sudo activity logs..."

# 1. Generate real sudo events
for i in {1..5}; do
    # Run a harmless sudo command
    echo "password123" | sudo -S -u root id > /dev/null 2>&1
    sleep 1
    # Run a failed sudo attempt (for diversity)
    echo "wrongpass" | sudo -S -u root id > /dev/null 2>&1 || true
    sleep 1
done

# 2. Ensure logs are written to disk
sync

# 3. Send logs to syslog explicitly to ensure immediate indexing
# (In case ELA is listening on UDP 514 but file tailing is slow)
if [ -f /var/log/auth.log ]; then
    logger -p auth.info -t sudo "sudo: ga : TTY=pts/0 ; PWD=/home/ga ; USER=root ; COMMAND=/usr/bin/id"
    logger -p auth.err -t sudo "sudo: auth : TTY=pts/0 ; PWD=/home/ga ; USER=root ; COMMAND=/usr/bin/ls"
fi

# 4. Wait a moment for indexing
sleep 5

# =====================================================
# UI Setup
# =====================================================

# Navigate to the Search page
# Note: The search URL often contains session-specific or dynamic hashes, 
# so we land on the main dashboard or search index.
SEARCH_URL="/event/index.do#/search/index"

ensure_firefox_on_ela "$SEARCH_URL"

# Wait for window
wait_for_window "Firefox" 30

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="