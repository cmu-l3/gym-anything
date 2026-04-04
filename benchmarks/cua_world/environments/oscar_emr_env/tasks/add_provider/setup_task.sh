#!/bin/bash
# Setup script for Add Provider task in OSCAR EMR

echo "=== Setting up Add Provider Task ==="

source /workspace/scripts/task_utils.sh

# 1. CLEANUP: Ensure the target provider and user do not exist from a previous run
# This is critical for the "Clean State" requirement
echo "Cleaning up any existing records for provider 100123 or user ewatson..."

# Delete from security table first (foreign key constraints might apply, though usually loose in Oscar)
oscar_query "DELETE FROM security WHERE user_name='ewatson'" 2>/dev/null || true
# Delete from provider table
oscar_query "DELETE FROM provider WHERE provider_no='100123'" 2>/dev/null || true

# 2. RECORD INITIAL STATE
# Get counts to verify strictly new additions later
INITIAL_PROVIDER_COUNT=$(oscar_query "SELECT COUNT(*) FROM provider" || echo "0")
INITIAL_SECURITY_COUNT=$(oscar_query "SELECT COUNT(*) FROM security" || echo "0")

echo "$INITIAL_PROVIDER_COUNT" > /tmp/initial_provider_count
echo "$INITIAL_SECURITY_COUNT" > /tmp/initial_security_count

# Record timestamp for anti-gaming (task start time)
date +%s > /tmp/task_start_timestamp

# 3. ENVIRONMENT SETUP
# Ensure Firefox is running and on the login page
echo "Launching/Resetting Firefox to Login Page..."
ensure_firefox_on_oscar

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Add Provider Task Setup Complete ==="
echo "Target Provider: Dr. Emily Watson (100123)"
echo "Target Username: ewatson"
echo "Ready for agent."