#!/bin/bash
echo "=== Setting up configure_email_forwarding task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure domain exists
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating acmecorp.test domain..."
    virtualmin create-domain --domain acmecorp.test --pass "TempPass123!" --web --dns --mail
fi

# 2. Ensure user 'sarah' exists
if ! virtualmin list-users --domain acmecorp.test --user sarah > /dev/null 2>&1; then
    echo "Creating user sarah..."
    virtualmin create-user \
        --domain acmecorp.test \
        --user sarah \
        --pass "SarahPass123!" \
        --real "Sarah Johnson" \
        --quota 500
else
    # 3. Reset state: Remove any existing forwarding to ensure clean start
    echo "Resetting user sarah state..."
    virtualmin modify-user \
        --domain acmecorp.test \
        --user sarah \
        --no-forward \
        --no-forward-destination
fi

# 4. Determine user home for verification later
SARAH_HOME=$(virtualmin list-users --domain acmecorp.test --user sarah --multiline | grep "Home directory:" | awk '{print $3}')
echo "$SARAH_HOME" > /tmp/sarah_home_path.txt

# 5. Launch Firefox and navigate to Edit Users page
ensure_virtualmin_ready
sleep 2

# Get domain ID for URL construction
DOM_ID=$(get_domain_id "acmecorp.test")

if [ -n "$DOM_ID" ]; then
    # Navigate directly to the user list for this domain
    navigate_to "https://localhost:10000/virtual-server/list_users.cgi?dom=${DOM_ID}"
else
    # Fallback to main page
    navigate_to "https://localhost:10000/virtual-server/"
fi
sleep 5

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="