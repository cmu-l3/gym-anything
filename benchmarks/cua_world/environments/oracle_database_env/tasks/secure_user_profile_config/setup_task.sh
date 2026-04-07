#!/bin/bash
# Setup for secure_user_profile_config task
# Resets HR user and cleans up any existing security profiles/functions

set -e

echo "=== Setting up Secure User Profile Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Reset State ---
echo "[2/4] Resetting security configuration..."

# We need to run as SYSTEM to manage profiles and users
# Note: Using SYSTEM to manage SYS objects (like password verify functions) is common in XE
# but strictly speaking verify functions often reside in SYS. 
# The task asks to create it in SYSTEM schema to avoid SYS-level permission complexity for the agent.

oracle_query "
-- Reset HR user
ALTER USER hr PROFILE DEFAULT;
ALTER USER hr ACCOUNT UNLOCK;
ALTER USER hr IDENTIFIED BY hr123;

-- Drop profile if exists (CASCADE removes assignment)
BEGIN
    EXECUTE IMMEDIATE 'DROP PROFILE SECURE_DEV_PROFILE CASCADE';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

-- Drop verification function if exists
BEGIN
    EXECUTE IMMEDIATE 'DROP FUNCTION SYSTEM.STRICT_PASS_VERIFY';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/
" "system" "OraclePassword123" > /dev/null 2>&1

echo "[3/4] Recording start time..."
date +%s > /tmp/task_start_time.txt

# --- Ensure DBeaver is ready ---
echo "[4/4] checking DBeaver..."
if ! which dbeaver-ce > /dev/null 2>&1; then
    echo "Installing DBeaver..."
    sudo snap install dbeaver-ce --classic 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "HR user reset to DEFAULT profile and UNLOCKED."
echo "Ready for agent to secure the account."