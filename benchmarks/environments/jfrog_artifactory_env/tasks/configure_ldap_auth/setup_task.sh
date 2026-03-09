#!/bin/bash
set -e
echo "=== Setting up LDAP configuration task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Artifactory is accessible
echo "Waiting for Artifactory..."
wait_for_artifactory 120 || {
    echo "ERROR: Artifactory not reachable"
    exit 1
}

# ==============================================================================
# Clean existing LDAP configuration
# We want the agent to start fresh. We will modify the system config to remove 
# any existing LDAP settings.
# ==============================================================================
echo "Cleaning existing LDAP settings..."
CURRENT_CONFIG=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/system/configuration" 2>/dev/null)

# Use Python to strip out <ldapSetting> blocks
echo "$CURRENT_CONFIG" | python3 -c "
import sys, re
config = sys.stdin.read()
# Regex to remove ldapSetting blocks. 
# Note: This is a rough cleanup suitable for the task setup to ensure key uniqueness.
cleaned = re.sub(r'<ldapSetting>.*?</ldapSetting>', '', config, flags=re.DOTALL)
print(cleaned)
" > /tmp/clean_config.xml 2>/dev/null || true

# Post the cleaned config back to Artifactory
if [ -s /tmp/clean_config.xml ]; then
    curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -X POST \
        -H "Content-Type: application/xml" \
        -d @/tmp/clean_config.xml \
        "${ARTIFACTORY_URL}/artifactory/api/system/configuration" > /dev/null 2>&1 || true
    echo "LDAP settings cleared."
fi

# Record initial state evidence (should be 0 LDAP settings)
echo "Recording initial state..."
INITIAL_CONFIG=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/system/configuration" 2>/dev/null)
echo "$INITIAL_CONFIG" > /tmp/initial_config.xml

# Ensure Firefox is running and pre-navigated to Admin
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082/ui/admin"
sleep 5

# Focus and maximize
focus_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="