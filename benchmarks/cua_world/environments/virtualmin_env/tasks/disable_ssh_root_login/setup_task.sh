#!/bin/bash
set -e
echo "=== Setting up task: disable_ssh_root_login ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 2. Configure SSH to ALLOW root login (The "Bad" Starting State)
SSHD_CONFIG="/etc/ssh/sshd_config"
echo "--- Configuring vulnerable state (PermitRootLogin yes) ---"

# Backup original if not exists
if [ ! -f "${SSHD_CONFIG}.bak" ]; then
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"
fi

# Use sed to ensure PermitRootLogin is set to yes
# Remove any existing PermitRootLogin lines (commented or not)
sed -i '/^PermitRootLogin/d' "$SSHD_CONFIG"
sed -i '/^#PermitRootLogin/d' "$SSHD_CONFIG"

# Append the bad setting
echo "PermitRootLogin yes" >> "$SSHD_CONFIG"

# Restart SSH to apply the bad configuration
systemctl restart sshd

# Verify initial state
if sudo sshd -T | grep -q "permitrootlogin yes"; then
    echo "State verified: SSH currently allows root login."
else
    echo "WARNING: Failed to set insecure starting state."
fi

# 3. Prepare Webmin/Firefox
# Ensure Virtualmin is running and accessible
ensure_virtualmin_ready

# Navigate to the Webmin Dashboard or Servers index to save a bit of time,
# but let the agent find the SSH module itself as per instructions.
navigate_to "https://localhost:10000/"

# 4. Capture initial state evidence
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

# Record file modification time of config (so we can check if it changes later)
stat -c %Y "$SSHD_CONFIG" > /tmp/initial_config_mtime.txt

echo "=== Task setup complete ==="