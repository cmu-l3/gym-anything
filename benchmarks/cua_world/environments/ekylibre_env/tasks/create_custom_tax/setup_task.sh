#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_custom_tax task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Ekylibre to be accessible
wait_for_ekylibre 120

# Detect tenant schema
# Ekylibre uses Apartment for multi-tenancy. We need to find the non-system schema.
TENANT_SCHEMA=$(ekylibre_db_query "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('public','information_schema','pg_catalog','pg_toast','postgis','lexicon') AND schema_name NOT LIKE 'pg_%' ORDER BY schema_name LIMIT 1;" | tr -d '[:space:]')
echo "$TENANT_SCHEMA" > /tmp/ekylibre_tenant_schema.txt
echo "Tenant schema detected: $TENANT_SCHEMA"

# Record initial tax count
# If schema found, search path must include it
if [ -n "$TENANT_SCHEMA" ]; then
    INITIAL_TAX_COUNT=$(ekylibre_db_query "SET search_path TO \"$TENANT_SCHEMA\", public; SELECT COUNT(*) FROM taxes;" | tr -d '[:space:]')
else
    # Fallback to public if no tenant found (though unlikely for Ekylibre)
    INITIAL_TAX_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM taxes;" | tr -d '[:space:]')
fi

echo "${INITIAL_TAX_COUNT:-0}" > /tmp/initial_tax_count.txt
echo "Initial tax count: ${INITIAL_TAX_COUNT:-0}"

# Ensure Firefox is open with Ekylibre dashboard
EKYLIBRE_URL=$(detect_ekylibre_url)
ensure_firefox_with_ekylibre "$EKYLIBRE_URL"
maximize_firefox

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="