#!/bin/bash
set -e
echo "=== Setting up create_server_alias task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure parent domain acmecorp.test exists (should be in env, but verify)
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Restoring acmecorp.test..."
    # Fallback creation if missing
    virtualmin create-domain --domain acmecorp.test --pass "GymAnything123!" --unix --dir --webmin --web --dns --mail --mysql
fi

# 2. Clean up target alias domain if it exists
if virtualmin_domain_exists "acme-corp.test"; then
    echo "Removing existing alias acme-corp.test..."
    virtualmin delete-domain --domain acme-corp.test 2>/dev/null || true
fi

# 3. Record initial state of domains
virtualmin list-domains --name-only > /tmp/initial_domains.txt

# 4. Prepare GUI
ensure_virtualmin_ready

# Navigate to the parent domain's dashboard to provide context
# We need the ID for the URL in Virtualmin 7/8
DOMAIN_ID=$(get_domain_id "acmecorp.test")
if [ -n "$DOMAIN_ID" ]; then
    navigate_to "https://localhost:10000/virtual-server/link.cgi/${DOMAIN_ID}/"
else
    # Fallback to main index if ID lookup fails
    navigate_to "https://localhost:10000/virtual-server/index.cgi"
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="