#!/bin/bash
set -e
echo "=== Setting up task: Create Financial Year 2017 ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Wait for Ekylibre to be ready
wait_for_ekylibre 120

# Identify the tenant schema (Ekylibre uses multi-tenancy schemas)
echo "identifying tenant schema..."
TENANT_SCHEMA=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c \
    "SELECT schema_name FROM information_schema.tables WHERE table_name = 'financial_years' AND table_schema NOT IN ('public', 'information_schema', 'pg_catalog', 'postgis', 'lexicon') LIMIT 1;" 2>/dev/null | head -1 || echo "")

if [ -z "$TENANT_SCHEMA" ]; then
    echo "WARNING: Could not find tenant schema. Defaulting to 'demo'."
    TENANT_SCHEMA="demo"
fi
echo "$TENANT_SCHEMA" > /tmp/ekylibre_tenant_schema.txt
echo "Using tenant schema: $TENANT_SCHEMA"

# Check if 2017 financial year already exists and clean it up (Start clean)
FY_2017_EXISTS=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c \
    "SET search_path TO ${TENANT_SCHEMA}, public; SELECT COUNT(*) FROM financial_years WHERE started_on = '2017-01-01' AND stopped_on = '2017-12-31';" 2>/dev/null || echo "0")

if [ "$FY_2017_EXISTS" != "0" ]; then
    echo "Cleaning up existing 2017 financial year..."
    docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -c \
        "SET search_path TO ${TENANT_SCHEMA}, public; DELETE FROM financial_years WHERE started_on = '2017-01-01' AND stopped_on = '2017-12-31';" 2>/dev/null || true
fi

# Record initial financial year count
INITIAL_FY_COUNT=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c \
    "SET search_path TO ${TENANT_SCHEMA}, public; SELECT COUNT(*) FROM financial_years;" 2>/dev/null || echo "0")
echo "$INITIAL_FY_COUNT" > /tmp/initial_fy_count.txt
echo "Initial financial year count: $INITIAL_FY_COUNT"

# Launch Firefox and navigate to Ekylibre dashboard
EKYLIBRE_URL=$(detect_ekylibre_url)
ensure_firefox_with_ekylibre "$EKYLIBRE_URL"
sleep 5
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="