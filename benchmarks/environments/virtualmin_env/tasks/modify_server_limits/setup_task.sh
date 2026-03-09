#!/bin/bash
set -e
echo "=== Setting up modify_server_limits task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Verify acmecorp.test exists or create it
# ---------------------------------------------------------------
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating acmecorp.test..."
    virtualmin create-domain \
        --domain acmecorp.test \
        --pass "AcmeCorp2024!" \
        --unix --dir --webmin --web --dns --mail --mysql 2>&1
    sleep 5
fi

# ---------------------------------------------------------------
# 2. Reset acmecorp.test to UNLIMITED/default state
# ---------------------------------------------------------------
echo "--- Resetting limits to defaults ---"

# Reset quota and bandwidth to unlimited
virtualmin modify-domain --domain acmecorp.test --quota UNLIMITED 2>/dev/null || true
virtualmin modify-domain --domain acmecorp.test --bw UNLIMITED 2>/dev/null || true

# Reset resource limits
virtualmin modify-limits --domain acmecorp.test \
    --max-mailboxes UNLIMITED \
    --max-aliases UNLIMITED \
    --max-dbs UNLIMITED 2>/dev/null || true

# Reset password to known initial value
virtualmin modify-domain --domain acmecorp.test --pass "AcmeCorp2024!" 2>/dev/null || true

sleep 2

# ---------------------------------------------------------------
# 3. Record initial state for anti-gaming verification
# ---------------------------------------------------------------
INITIAL_INFO=$(virtualmin list-domains --domain acmecorp.test --multiline 2>/dev/null)
echo "$INITIAL_INFO" > /tmp/initial_server_state.txt
# Also record initial password hash
grep "^acmecorp:" /etc/shadow > /tmp/initial_shadow_entry.txt 2>/dev/null || true

# ---------------------------------------------------------------
# 4. Prepare Browser
# ---------------------------------------------------------------
ensure_virtualmin_ready

# Navigate to the domain summary page for acmecorp.test
DOMAIN_ID=$(get_domain_id "acmecorp.test")
navigate_to "${VIRTUALMIN_URL}/virtual-server/summary_domain.cgi?dom=${DOMAIN_ID}"
sleep 5

# Maximize and focus
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="