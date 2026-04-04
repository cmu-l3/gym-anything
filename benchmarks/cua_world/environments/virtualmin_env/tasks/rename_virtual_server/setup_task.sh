#!/bin/bash
set -e
echo "=== Setting up rename_virtual_server task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Ensure clean state
# ---------------------------------------------------------------

# Remove target domain if it exists (from failed previous attempt)
if virtualmin_domain_exists "acmetech.test"; then
    echo "WARNING: acmetech.test already exists, removing for clean start..."
    virtualmin delete-domain --domain acmetech.test --yes 2>/dev/null || true
    sleep 5
fi

# ---------------------------------------------------------------
# 2. Ensure source domain acmecorp.test exists with features
# ---------------------------------------------------------------
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating source domain acmecorp.test..."
    virtualmin create-domain \
        --domain acmecorp.test \
        --pass "AcmeCorp2024!" \
        --unix \
        --dir \
        --webmin \
        --web \
        --dns \
        --mail \
        --mysql 2>&1 | tail -5
    sleep 5
fi

# Ensure features are enabled
echo "Ensuring features are enabled for acmecorp.test..."
virtualmin enable-feature --domain acmecorp.test --web --dns --mail --mysql 2>/dev/null || true

# Record initial state
DOMAIN_ID=$(get_domain_id "acmecorp.test")
echo "$DOMAIN_ID" > /tmp/initial_domain_id.txt

# ---------------------------------------------------------------
# 3. Setup Firefox
# ---------------------------------------------------------------
ensure_virtualmin_ready
sleep 2

# Navigate to acmecorp.test summary page
if [ -n "$DOMAIN_ID" ]; then
    navigate_to "https://localhost:10000/virtual-server/summary.cgi?dom=${DOMAIN_ID}"
else
    navigate_to "https://localhost:10000/virtual-server/index.cgi"
fi
sleep 5

# Capture initial state screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="