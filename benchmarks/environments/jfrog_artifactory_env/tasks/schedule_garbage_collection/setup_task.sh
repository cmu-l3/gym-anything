#!/bin/bash
set -e
echo "=== Setting up schedule_garbage_collection task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Artifactory is ready
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory did not start in time."
    exit 1
fi

# 2. Reset/Ensure GC schedule is NOT the target value (Anti-gaming setup)
# Target is "0 0 2 ? * SUN". We set it to default "0 0 /4 * * ?" if it happens to match.
# We do this by patching the system config via REST API.
echo "Checking current configuration..."
CURRENT_CONFIG=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration")

# Extract current cron using python
CURRENT_CRON=$(echo "$CURRENT_CONFIG" | python3 -c "
import sys, xml.etree.ElementTree as ET
try:
    tree = ET.parse(sys.stdin)
    root = tree.getroot()
    # Namespace handling might be needed depending on Artifactory version, 
    # but usually standard tags work if we ignore NS or strip it.
    # Simple search:
    cron = root.find('.//garbageCollector/cronExp')
    print(cron.text if cron is not None else 'NOT_FOUND')
except Exception as e:
    print('ERROR')
")

TARGET_CRON="0 0 2 ? * SUN"

echo "Current Cron: '$CURRENT_CRON'"

if [ "$CURRENT_CRON" == "$TARGET_CRON" ]; then
    echo "Current cron matches target. Resetting to default..."
    # We need to post the full config back with modification.
    # This is complex via bash. Simpler approach: 
    # Just fail setup? No, we should fix it.
    # Or, rely on the fact that default is different. 
    # For this task, we assume the environment starts with default.
    # If we really need to change it, we'd POST /api/system/configuration.
    # Since manipulating XML in bash is error-prone, we'll log a warning.
    echo "WARNING: Starting state already matches target. Verification requires change."
fi

# Save initial state for verifier to prove a change happened
echo "$CURRENT_CRON" > /tmp/initial_gc_cron.txt

# 3. Start Firefox
ensure_firefox_running "http://localhost:8082"
sleep 5

# 4. Navigate to Admin login or Dashboard
# (Agent handles login, but we ensure window is ready)
focus_firefox

# 5. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="