#!/bin/bash
set -e
echo "=== Setting up configure_email_auth_dns task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Ensure the target domain exists (localbiz.test is pre-seeded, but verify)
if ! virtualmin_domain_exists "localbiz.test"; then
    echo "ERROR: localbiz.test domain does not exist. Re-creating..."
    virtualmin create-domain --domain localbiz.test --pass "GymAnything123!" --unix --dir --webmin --web --dns --mail --mysql
fi

# 3. CLEANUP: Remove existing SPF/DMARC records to ensure clean state
# Virtualmin creates a default SPF record usually. We want the agent to create/edit it to specific values.
echo "Cleaning existing records..."
# Remove default SPF if exists
virtualmin modify-dns --domain localbiz.test --remove-record "localbiz.test. TXT" 2>/dev/null || true
# Remove DMARC if exists
virtualmin modify-dns --domain localbiz.test --remove-record "_dmarc.localbiz.test. TXT" 2>/dev/null || true

# Apply changes to ensure zone is clean and serial is updated
virtualmin modify-dns --domain localbiz.test --apply 2>/dev/null || true
sleep 2

# 4. Record Initial State (for verification)
# Get current SOA serial number
INITIAL_SERIAL=$(virtualmin get-dns --domain localbiz.test | grep "SOA" | grep -oE '[0-9]{10}' | head -1 || echo "0")
echo "$INITIAL_SERIAL" > /tmp/initial_dns_serial.txt

# Count TXT records
INITIAL_TXT_COUNT=$(virtualmin get-dns --domain localbiz.test | grep "TXT" | wc -l)
echo "$INITIAL_TXT_COUNT" > /tmp/initial_txt_count.txt

echo "Initial Serial: $INITIAL_SERIAL"
echo "Initial TXT Count: $INITIAL_TXT_COUNT"

# 5. Prepare Firefox
ensure_virtualmin_ready

# Navigate specifically to the DNS Records page for localbiz.test to save agent time
# Virtualmin 7/8 uses numeric IDs for domains in URLs often, but list_records.cgi usually accepts dom=ID
DOMAIN_ID=$(get_domain_id "localbiz.test")
echo "Navigating to DNS records for domain ID: $DOMAIN_ID"

if [ -n "$DOMAIN_ID" ]; then
    navigate_to "https://localhost:10000/virtual-server/list_records.cgi?dom=${DOMAIN_ID}"
else
    # Fallback to main page if ID fail
    navigate_to "https://localhost:10000/virtual-server/"
fi

# 6. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="