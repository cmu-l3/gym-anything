#!/bin/bash
echo "=== Setting up modify_php_config task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure the target domain exists
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "ERROR: acmecorp.test domain does not exist. Environment may be corrupted."
    exit 1
fi

# Reset PHP configuration to standard defaults to ensure task is solvable/testable
# (Prevents cases where the target values might already be set from a previous dirty run)
echo "Resetting PHP configuration for acmecorp.test..."
virtualmin modify-php-ini --domain acmecorp.test --ini-name upload_max_filesize --ini-value "2M" 2>/dev/null || true
virtualmin modify-php-ini --domain acmecorp.test --ini-name post_max_size --ini-value "8M" 2>/dev/null || true
virtualmin modify-php-ini --domain acmecorp.test --ini-name memory_limit --ini-value "128M" 2>/dev/null || true
virtualmin modify-php-ini --domain acmecorp.test --ini-name max_execution_time --ini-value "60" 2>/dev/null || true

# Record initial state for verification logic (to prove values changed)
echo "Recording initial state..."
INITIAL_STATE_FILE="/tmp/initial_php_state.json"
cat > "$INITIAL_STATE_FILE" << EOF
{
  "upload_max_filesize": "$(virtualmin list-php-ini --domain acmecorp.test --ini-name upload_max_filesize --simple 2>/dev/null)",
  "post_max_size": "$(virtualmin list-php-ini --domain acmecorp.test --ini-name post_max_size --simple 2>/dev/null)",
  "memory_limit": "$(virtualmin list-php-ini --domain acmecorp.test --ini-name memory_limit --simple 2>/dev/null)",
  "max_execution_time": "$(virtualmin list-php-ini --domain acmecorp.test --ini-name max_execution_time --simple 2>/dev/null)"
}
EOF

# Ensure Virtualmin is accessible and user is logged in
ensure_virtualmin_ready

# Navigate to the domain's dashboard to give the agent a fair start
# We use the domain ID to construct the URL for Virtualmin 7/8 compatibility
DOM_ID=$(get_domain_id "acmecorp.test")
navigate_to "https://localhost:10000/virtual-server/link.cgi/${DOM_ID}/"
sleep 5

# Maximize Firefox for visibility
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="