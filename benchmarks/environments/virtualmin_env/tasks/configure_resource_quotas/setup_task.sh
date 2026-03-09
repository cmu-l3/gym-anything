#!/bin/bash
set -e
echo "=== Setting up task: configure_resource_quotas ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure the required domains exist (idempotent check)
# If they don't exist (fresh environment), we rely on install_virtualmin.sh having created them
# or we create them now if missing.
DOMAINS=("acmecorp.test" "greenleaf.test" "craftworks.test")

for domain in "${DOMAINS[@]}"; do
    if ! virtualmin_domain_exists "$domain"; then
        echo "Creating missing domain: $domain"
        virtualmin create-domain --domain "$domain" --pass "TempPass123!" --unix --dir --webmin --web --dns --mysql >/dev/null 2>&1
    fi
done

# Reset quotas to UNLIMITED for all domains to ensure a clean starting state
echo "--- Resetting quotas to unlimited ---"
for domain in "${DOMAINS[@]}"; do
    # Set quota to unlimited (0 = unlimited in Virtualmin usually, or 'UNLIMITED')
    virtualmin modify-domain --domain "$domain" --quota UNLIMITED --bw-limit NONE >/dev/null 2>&1 || true
    echo "  Reset quotas for $domain"
    
    # Record initial state for change detection
    virtualmin list-domains --domain "$domain" --multiline > "/tmp/initial_state_${domain}.txt" 2>/dev/null || true
done

# Ensure Firefox is open and logged in
ensure_virtualmin_ready

# Navigate to Virtualmin main page
navigate_to "https://localhost:10000/virtual-server/index.cgi"
sleep 2

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="