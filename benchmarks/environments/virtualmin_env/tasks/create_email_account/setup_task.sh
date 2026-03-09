#!/bin/bash
echo "=== Setting up create_email_account task ==="

source /workspace/scripts/task_utils.sh

# Remove the target user if they already exist from a previous run
if virtualmin list-users --domain acmecorp.test 2>/dev/null | grep -q "^john\.smith@acmecorp\.test"; then
    echo "WARNING: john.smith@acmecorp.test already exists, removing..."
    virtualmin delete-user \
        --domain acmecorp.test \
        --user john.smith 2>&1 | tail -3 || true
    sleep 2
fi

# Ensure Virtualmin is accessible in Firefox
ensure_virtualmin_ready
sleep 2

# Navigate to the "Create User" page for acmecorp.test
# Virtualmin 8.x requires numeric domain ID (not name) in URL
ACMECORP_ID=$(get_domain_id "acmecorp.test")
navigate_to "https://localhost:10000/virtual-server/edit_user.cgi?dom=${ACMECORP_ID}&new=1"
sleep 5

take_screenshot /tmp/create_email_account_start.png
echo "=== create_email_account task setup complete ==="
echo "Agent should see the Add User form for acmecorp.test in Firefox."
