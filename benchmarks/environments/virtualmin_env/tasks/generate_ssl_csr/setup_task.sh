#!/bin/bash
set -e
echo "=== Setting up generate_ssl_csr task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Anti-gaming: Record start time
date +%s > /tmp/task_start_time.txt

# 2. Cleanup: Remove any existing result file
rm -f /home/ga/Documents/acmecorp.csr

# 3. Ensure target domain exists and has SSL enabled
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating acmecorp.test..."
    virtualmin create-domain --domain acmecorp.test --pass "GymAnything123!" --unix --dir --webmin --web --dns --mail --mysql --ssl
else
    # Ensure SSL feature is enabled
    virtualmin enable-feature --domain acmecorp.test --ssl || true
fi

# 4. App State: Ensure Virtualmin is open and logged in
ensure_virtualmin_ready

# 5. Navigation: Go to the domain summary to start
# We don't go directly to the SSL page to force the agent to navigate the menu
ID=$(get_domain_id "acmecorp.test")
navigate_to "${VIRTUALMIN_URL}/virtual-server/edit_domain.cgi?dom=${ID}"

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="