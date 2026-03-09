#!/bin/bash
echo "=== Setting up create_email_alias task ==="

source /workspace/scripts/task_utils.sh

# Remove the support alias if it already exists from a previous run
if virtualmin_alias_exists "brightstar.test" "support"; then
    echo "WARNING: support@brightstar.test alias already exists, removing it..."
    virtualmin delete-alias \
        --domain brightstar.test \
        --from support 2>&1 | tail -3 || true
    sleep 2
fi

# Ensure Virtualmin is accessible in Firefox
ensure_virtualmin_ready
sleep 2

# Navigate to the Email Aliases page for brightstar.test
# Virtualmin 8.x requires numeric domain ID (not name) in URL
BRIGHTSTAR_ID=$(get_domain_id "brightstar.test")
navigate_to "https://localhost:10000/virtual-server/list_aliases.cgi?dom=${BRIGHTSTAR_ID}"
sleep 5

take_screenshot /tmp/create_email_alias_start.png
echo "=== create_email_alias task setup complete ==="
echo "Agent should see the Email Aliases page for brightstar.test in Firefox."
