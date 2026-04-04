#!/bin/bash
echo "=== Setting up migrate_dns_office365 task ==="

source /workspace/scripts/task_utils.sh

# Target domain
DOMAIN="acmecorp.test"

# 1. Ensure Domain Exists
if ! virtualmin_domain_exists "$DOMAIN"; then
    echo "Creating missing domain $DOMAIN..."
    virtualmin create-domain --domain "$DOMAIN" --pass "GymAnything123!" --unix --dir --webmin --web --dns --mail --mysql
fi

# 2. Reset DNS to known "Local" state
echo "Resetting DNS records for $DOMAIN to local default..."

# Reset zone to default
virtualmin reset-dns --domain "$DOMAIN" --all-records

# Ensure default MX exists (and points to domain)
# Remove any weird MX first just in case
virtualmin modify-dns --domain "$DOMAIN" --remove-type MX
virtualmin modify-dns --domain "$DOMAIN" --add-record "$DOMAIN. MX 5 $DOMAIN."

# Ensure default SPF exists
virtualmin modify-dns --domain "$DOMAIN" --remove-type TXT --value "v=spf1"
virtualmin modify-dns --domain "$DOMAIN" --add-record "$DOMAIN. TXT \"v=spf1 a mx -all\""

# Ensure no autodiscover CNAME
virtualmin modify-dns --domain "$DOMAIN" --remove-record "autodiscover CNAME" 2>/dev/null || true

# Ensure no SRV record
virtualmin modify-dns --domain "$DOMAIN" --remove-type SRV 2>/dev/null || true

echo "DNS reset complete."

# 3. Record timestamp
date +%s > /tmp/task_start_time.txt

# 4. Prepare UI
ensure_virtualmin_ready
sleep 2

# Navigate to DNS Records page for the domain
# Using ID lookup for robustness with Virtualmin 8.x
DOM_ID=$(get_domain_id "$DOMAIN")
navigate_to "https://localhost:10000/virtual-server/list_records.cgi?dom=${DOM_ID}"
sleep 5

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png
virtualmin get-dns --domain "$DOMAIN" > /tmp/initial_dns_state.txt

echo "=== Task setup complete ==="