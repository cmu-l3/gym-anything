#!/bin/bash
# Setup script for Add Satellite Clinic task in OSCAR EMR

echo "=== Setting up Add Satellite Clinic Task ==="

source /workspace/scripts/task_utils.sh

# ==============================================================================
# 1. Clean up previous runs (Anti-gaming / Idempotency)
# ==============================================================================
TARGET_NAME="West End Clinic"

echo "Checking for existing clinic location: '$TARGET_NAME'..."
# Delete from 'branch' table if exists
oscar_query "DELETE FROM branch WHERE location LIKE '%${TARGET_NAME}%' OR description LIKE '%${TARGET_NAME}%'" 2>/dev/null || true

# ==============================================================================
# 2. Record Initial State
# ==============================================================================
# Record timestamp for anti-gaming (to check if record created during task)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Record initial count of branches
INITIAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM branch" || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_branch_count
echo "Initial branch count: $INITIAL_COUNT"

# ==============================================================================
# 3. Application Setup
# ==============================================================================
# Open Firefox on OSCAR login page
ensure_firefox_on_oscar

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo ""
echo "TASK: Add 'West End Clinic' as a new branch/location."
echo "  - Name:    West End Clinic"
echo "  - Address: 880 West Drive"
echo "  - City:    Toronto, ON"
echo "  - Phone:   416-555-9000"
echo ""
echo "Credentials: oscardoc / oscar / PIN: 1117"
echo ""