#!/bin/bash
set -e
echo "=== Setting up Configure Sales Stage task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Clean up previous state (Anti-Gaming / Idempotency)
# ---------------------------------------------------------------
echo "--- Cleaning up any existing 'Verbal' sales stages ---"

# We rename any existing conflicting records to avoid unique constraint violations
# and set them to inactive.
CLEANUP_QUERY="UPDATE C_SalesStage SET Value = Value || '_OLD_' || TO_CHAR(NOW(), 'YYYYMMDDHH24MISS'), Name = Name || ' (Archived)', IsActive='N' WHERE Value='Verbal' OR Name='Verbal Commitment';"

# Execute cleanup query
idempiere_query "$CLEANUP_QUERY" || echo "Cleanup warning: Query might have failed if table locked or empty"

# ---------------------------------------------------------------
# 2. Ensure iDempiere is running and reachable
# ---------------------------------------------------------------
echo "--- Ensuring iDempiere is ready ---"

# Navigate to dashboard to start fresh
navigate_to_dashboard

# Maximize Firefox window to ensure elements are visible for the agent
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -xa "Firefox" 2>/dev/null || true

# ---------------------------------------------------------------
# 3. Capture Initial State
# ---------------------------------------------------------------
echo "--- Capturing initial state ---"
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="