#!/bin/bash
echo "=== Setting up create_sub_server task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous attempts (Idempotency)
if virtualmin_domain_exists "blog.greenwidgets.test"; then
    echo "Cleaning up pre-existing sub-server..."
    virtualmin delete-domain --domain blog.greenwidgets.test --yes > /dev/null 2>&1 || true
    sleep 3
fi

# 2. Verify parent domain exists (Critical dependency)
if ! virtualmin_domain_exists "greenwidgets.test"; then
    echo "ERROR: Parent domain greenwidgets.test missing. Re-creating..."
    # Re-create the parent if it was deleted
    virtualmin create-domain --domain greenwidgets.test --pass "GymAnything123!" --unix --dir --webmin --web --dns --mail --mysql > /dev/null 2>&1 || true
fi

# 3. Record initial state
INITIAL_DOMAIN_COUNT=$(virtualmin list-domains --name-only 2>/dev/null | wc -l)
echo "$INITIAL_DOMAIN_COUNT" > /tmp/initial_domain_count.txt

# 4. Prepare Application (Firefox + Virtualmin)
ensure_virtualmin_ready
sleep 2

# Navigate to the "Create Virtual Server" page to save the agent one click/search
# But strictly speaking, the agent should find it. Let's just go to the parent domain dashboard.
GW_ID=$(get_domain_id "greenwidgets.test")
if [ -n "$GW_ID" ]; then
    navigate_to "${VIRTUALMIN_URL}/virtual-server/summary.cgi?dom=${GW_ID}"
else
    navigate_to "${VIRTUALMIN_URL}/virtual-server/index.cgi"
fi
sleep 5

# 5. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="