#!/bin/bash
set -e
echo "=== Setting up firewall rules task ==="

# Source utilities (if available, otherwise define local helpers)
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback minimal helpers if utility script missing
    take_screenshot() {
        DISPLAY=:1 scrot "$1" 2>/dev/null || true
    }
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure iptables is installed
if ! command -v iptables &> /dev/null; then
    apt-get update && apt-get install -y iptables
fi

# 1. ESTABLISH BASELINE STATE
# We want a clean slate for the target rules, but we MUST preserve access to Webmin/SSH
echo "Configuring baseline iptables rules..."

# Check if we have basic connectivity rules, if not, add them
iptables -L INPUT -n > /dev/null 2>&1 || true

# Helper to add rule if missing
ensure_rule() {
    local port=$1
    if ! iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
    fi
}

ensure_rule 22
ensure_rule 80
ensure_rule 443
ensure_rule 10000

# 2. CLEAN UP PREVIOUS RUNS
# Remove any existing rules for our specific task targets to ensure the agent actually adds them
echo "Cleaning up target rules..."
# Delete any rule referencing port 8443
while iptables -D INPUT -p tcp --dport 8443 -j ACCEPT 2>/dev/null; do :; done
# Delete any rule referencing port 9090
while iptables -D INPUT -p tcp --dport 9090 -j ACCEPT 2>/dev/null; do :; done
# Delete any rule referencing the block range
while iptables -D INPUT -s 198.51.100.0/24 -j DROP 2>/dev/null; do :; done
while iptables -D INPUT -s 198.51.100.0/24 -j REJECT 2>/dev/null; do :; done

# Save this clean state to Webmin's config file so it sees the "clean" state
# Webmin typically uses /etc/iptables.up.rules or similar depending on distro,
# but usually reads from live kernel or its own save file.
# We'll force save to common locations.
iptables-save > /etc/iptables.up.rules 2>/dev/null || true

# Record initial rule count for anti-gaming
iptables -L INPUT -n | grep -c "^[A-Z]" > /tmp/initial_rule_count.txt

# 3. GUI SETUP
# Ensure Webmin is running
systemctl restart webmin 2>/dev/null || true

# Launch Firefox and login
# We use the utility function if available, or manual fallback
if type ensure_virtualmin_ready &>/dev/null; then
    ensure_virtualmin_ready
    # Navigate to Dashboard (agent must find Networking > Linux Firewall)
    navigate_to "https://localhost:10000/"
else
    # Fallback manual setup
    if ! pgrep -f firefox > /dev/null; then
        su - ga -c "DISPLAY=:1 firefox https://localhost:10000/ &"
        sleep 10
    fi
    # Assume logged in or auto-login handled by env
    DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 4. CAPTURE EVIDENCE
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="