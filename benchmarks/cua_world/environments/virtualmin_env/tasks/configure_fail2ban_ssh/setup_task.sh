#!/bin/bash
echo "=== Setting up configure_fail2ban_ssh task ==="

source /workspace/scripts/task_utils.sh

# 1. Install Fail2Ban if not present (should be there, but safety first)
if ! dpkg -l | grep -q fail2ban; then
    echo "Installing Fail2Ban..."
    apt-get update && apt-get install -y fail2ban
fi

# 2. Reset Configuration to Defaults (Anti-Gaming / Clean Slate)
# We want to ensure the agent actually does the work.
# Default usually: maxretry=5, bantime=600
echo "Resetting Fail2Ban configuration..."

# Create a clean jail.local or modify existing to standard defaults
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 600
findtime = 600
maxretry = 5

[sshd]
enabled = true
EOF

# Restart to apply defaults
systemctl restart fail2ban
sleep 2

# Verify current state is NOT the target state
CURRENT_RETRY=$(fail2ban-client get sshd maxretry 2>/dev/null || echo "0")
CURRENT_BAN=$(fail2ban-client get sshd bantime 2>/dev/null || echo "0")

echo "Initial State - MaxRetry: $CURRENT_RETRY, BanTime: $CURRENT_BAN"

# 3. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 4. Prepare Browser
# Ensure Virtualmin is ready and logged in
ensure_virtualmin_ready

# Navigate to the Fail2Ban module if possible to help the agent get started,
# or just leave at dashboard. Let's navigate to the module list or dashboard.
# Webmin's Fail2Ban module is usually at /fail2ban/
navigate_to "https://localhost:10000/fail2ban/"
sleep 5

# 5. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="