#!/bin/bash
set -e
echo "=== Setting up create_journal_entry task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Ekylibre to be ready
wait_for_ekylibre 120

# Determine the tenant schema (demo farm)
# We assume the default demo tenant. If strict isolation is used, we might need to find it.
# Usually 'demo' or the first schema that isn't public/information_schema.
TENANT_SCHEMA=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c "SELECT schema FROM tenants WHERE schema != 'public' LIMIT 1;" 2>/dev/null || echo "demo")
if [ -z "$TENANT_SCHEMA" ]; then
    TENANT_SCHEMA="demo"
fi
echo "Tenant schema identified: $TENANT_SCHEMA"
echo "$TENANT_SCHEMA" > /tmp/ekylibre_tenant_schema.txt

# Record initial journal entry count
# We look for entries around the target date to ensure we track the specific addition
INITIAL_COUNT=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c "SET search_path TO \"$TENANT_SCHEMA\", public; SELECT COUNT(*) FROM journal_entries;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_journal_entry_count.txt
echo "Initial journal entry count: $INITIAL_COUNT"

# Verify accounts exist (for debugging/verification readiness)
echo "Verifying Chart of Accounts..."
docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c "SET search_path TO \"$TENANT_SCHEMA\", public; SELECT number, name FROM accounts WHERE number LIKE '6155%' OR number LIKE '512%' LIMIT 5;" 2>/dev/null || true

# Setup browser
EKYLIBRE_URL=$(detect_ekylibre_url)
# Navigate to the Accounting Dashboard or Journal Entries list to save agent some clicks,
# but not directly to 'new' to force navigation skill.
TARGET_URL="${EKYLIBRE_URL}/backend/journal_entries"

echo "Navigating Firefox to $TARGET_URL..."
ensure_firefox_with_ekylibre "$TARGET_URL"
sleep 5
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="