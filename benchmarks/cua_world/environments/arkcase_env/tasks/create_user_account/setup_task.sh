#!/bin/bash
echo "=== Setting up Create User Account Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure port-forward is active for API/UI access
ensure_portforward

# Wait for ArkCase to be accessible
wait_for_arkcase

# 1. Clean up: Ensure the user does not already exist in LDAP
echo "Checking/Cleaning LDAP state..."
LDAP_POD=$(kubectl get pods -n arkcase --no-headers 2>/dev/null | grep ldap | awk '{print $1}' | head -1)

if [ -n "$LDAP_POD" ]; then
    # Check if user exists
    USER_CHECK=$(kubectl exec -n arkcase "$LDAP_POD" -- samba-tool user list 2>/dev/null | grep -c "elena.rodriguez" || echo "0")
    
    if [ "$USER_CHECK" -gt 0 ]; then
        echo "User 'elena.rodriguez' exists. Deleting..."
        kubectl exec -n arkcase "$LDAP_POD" -- samba-tool user delete "elena.rodriguez" 2>/dev/null || true
        sleep 2
    else
        echo "User 'elena.rodriguez' does not exist (clean state)."
    fi
else
    echo "WARNING: LDAP pod not found. Cannot verify initial state."
fi

# 2. Ensure Firefox is open and logged in
echo "Launching Firefox..."
# Check if Firefox is already running
if ! pgrep -f firefox > /dev/null; then
    # Start Firefox on the home page
    ensure_firefox_on_arkcase "${ARKCASE_URL}/home.html"
else
    # Navigate to home page if already running
    navigate_to "${ARKCASE_URL}/home.html"
fi

# Handle any SSL warnings
handle_ssl_warning

# Perform auto-login to get to Dashboard
auto_login_arkcase "${ARKCASE_URL}/home.html"

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

# 4. Verify initial state recorded
echo "Initial state recorded."
ls -l /tmp/task_initial.png

echo "=== Setup complete ==="