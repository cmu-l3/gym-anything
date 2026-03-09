#!/bin/bash
set -e
echo "=== Setting up create_ftp_users task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure acmecorp.test exists (it should be pre-seeded, but verify)
if ! virtualmin list-domains --name-only 2>/dev/null | grep -q "^acmecorp.test$"; then
    echo "Creating acmecorp.test domain..."
    virtualmin create-domain --domain acmecorp.test --pass "TempPass123!" --unix --dir --webmin --web --dns --mail --mysql
fi

# Clean up any previous attempts (idempotency)
echo "Cleaning up previous users..."
for u in alice_dev dave_uploads; do
    if virtualmin list-users --domain acmecorp.test --user "$u" >/dev/null 2>&1; then
        virtualmin delete-user --domain acmecorp.test --user "$u" >/dev/null 2>&1 || true
    fi
    # Also check system level just in case
    if id "$u" >/dev/null 2>&1; then
        userdel -f "$u" >/dev/null 2>&1 || true
    fi
done

# Remove the uploads directory if it exists to test agent's creation ability
rm -rf /home/acmecorp/public_html/uploads

# Record initial user count for anti-gaming
INITIAL_COUNT=$(virtualmin list-users --domain acmecorp.test --user-only 2>/dev/null | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_user_count.txt

# Ensure Virtualmin is ready in Firefox
ensure_virtualmin_ready

# Navigate to "Edit Users" for acmecorp.test
# We need the domain ID for the URL
DOM_ID=$(get_domain_id "acmecorp.test")
navigate_to "https://localhost:10000/virtual-server/list_users.cgi?dom=${DOM_ID}"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="