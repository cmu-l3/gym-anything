#!/bin/bash
set -e
echo "=== Setting up configure_shared_workspace task ==="

# Source environment utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure 'acmecorp' user exists (usually created by environment setup, but safety first)
if ! id "acmecorp" >/dev/null 2>&1; then
    useradd -m -s /bin/bash acmecorp
    echo "acmecorp:GymAnything123!" | chpasswd
fi

# 2. Create the specific users 'jordan' and 'alex' for this scenario
# We create them as standard system users
echo "--- Ensuring users jordan and alex exist ---"
for user in jordan alex; do
    if ! id "$user" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$user"
        echo "${user}:Password123!" | chpasswd
    fi
done

# 3. CLEANUP: Remove artifacts from previous runs to ensure clean state
echo "--- Cleaning up previous state ---"
# Remove the directory
rm -rf /home/acmecorp/campaign_2026

# Remove the group if it exists
if getent group creative_team >/dev/null; then
    groupdel creative_team
fi

# Remove users from the group (redundant if group deleted, but safe)
for user in jordan alex; do
    # check if user is in creative_team (grep logic)
    if id -nG "$user" | grep -qw "creative_team"; then
        gpasswd -d "$user" creative_team 2>/dev/null || true
    fi
done

# 4. GUI Setup
# Ensure Virtualmin is ready and open in Firefox
ensure_virtualmin_ready

# Navigate to "Users and Groups" module directly to give a hint/starting point
# System > Users and Groups
navigate_to "https://localhost:10000/useradmin/?xnavigation=1"
sleep 4

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="