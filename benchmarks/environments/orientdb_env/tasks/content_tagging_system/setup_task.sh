#!/bin/bash
set -e
echo "=== Setting up Content Tagging System task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# === CLEAN STATE PREPARATION ===
# We must ensure the Tags and HasTag classes do NOT exist so the agent has to create them.
echo "Cleaning up any previous task artifacts..."

# Drop HasTag edge class if exists (must be done before dropping vertices)
if orientdb_class_exists "demodb" "HasTag"; then
    echo "Dropping existing HasTag class..."
    orientdb_sql "demodb" "DROP CLASS HasTag UNSAFE" > /dev/null 2>&1 || true
fi

# Drop Tags vertex class if exists
if orientdb_class_exists "demodb" "Tags"; then
    echo "Dropping existing Tags class..."
    orientdb_sql "demodb" "DROP CLASS Tags UNSAFE" > /dev/null 2>&1 || true
fi

# Remove the report file if it exists
rm -f /home/ga/tagging_report.json

# Record initial state checks (should be false/zero)
INITIAL_TAGS_EXIST=$(orientdb_class_exists "demodb" "Tags" && echo "true" || echo "false")
echo "Initial Tags class exists: $INITIAL_TAGS_EXIST" > /tmp/initial_state_check.txt

# === APP SETUP ===
# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="