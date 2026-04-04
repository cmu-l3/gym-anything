#!/bin/bash
set -e
echo "=== Setting up set_out_of_office_delegate task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ── 1. Ensure ArkCase is accessible ──────────────────────────────────────────
ensure_portforward
wait_for_arkcase

# ── 2. Create the Delegate User (Sally Acm) ──────────────────────────────────
echo "Ensuring user sally-acm exists..."
# Create user payload
USER_PAYLOAD='{
    "username": "sally-acm@dev.arkcase.com",
    "firstName": "Sally",
    "lastName": "Acm",
    "email": "sally-acm@dev.arkcase.com",
    "password": "Password123!",
    "enabled": true,
    "roles": ["ROLE_USER", "ROLE_CASE_WORKER"]
}'

# Attempt create via API (ignore error if already exists)
# We use the helper function from task_utils.sh
arkcase_api POST "users" "$USER_PAYLOAD" 2>/dev/null || true

# ── 3. Reset/Clear Existing Delegates ────────────────────────────────────────
echo "Clearing existing delegates for admin..."
# We fetch current profile to find delegate IDs, then delete them.
# This ensures we start with a clean slate.
PROFILE_JSON=$(arkcase_api GET "users/profile" 2>/dev/null)
DELEGATE_IDS=$(echo "$PROFILE_JSON" | python3 -c "import sys, json; print(' '.join([d['id'] for d in json.load(sys.stdin).get('delegates', [])]))" 2>/dev/null || echo "")

for id in $DELEGATE_IDS; do
    echo "Removing existing delegate ID: $id"
    arkcase_api DELETE "users/profile/delegates/$id" 2>/dev/null || true
done

# Record initial state (should be 0 delegates)
echo "0" > /tmp/initial_delegate_count.txt

# ── 4. Launch Firefox and Login ──────────────────────────────────────────────
ensure_firefox_on_arkcase "${ARKCASE_URL}/home.html"
handle_ssl_warning

# Perform auto-login
focus_firefox
maximize_firefox
auto_login_arkcase "${ARKCASE_URL}/home.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="