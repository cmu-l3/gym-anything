#!/bin/bash
# Task: crop_rotation_plan_for_compliance
# Setup: Record baseline state of activity_productions, navigate to the
# Productions/Activities overview page as starting point.

echo "=== Setting up crop_rotation_plan_for_compliance ==="

source /workspace/scripts/task_utils.sh

# Fallback definition for ekylibre_db_query if not sourced
if ! type ekylibre_db_query &>/dev/null; then
    ekylibre_db_query() {
        local query="$1"
        docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A \
            -c "SET search_path TO demo,lexicon,public; $query" 2>/dev/null || echo ""
    }
fi

# Wait for Ekylibre to be accessible
wait_for_ekylibre 120
EKYLIBRE_BASE=$(detect_ekylibre_url)

# --- Record baseline: current count of activity_productions ---
INITIAL_PROD_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM activity_productions;" | tr -d '[:space:]' || echo "0")
INITIAL_PROD_COUNT=${INITIAL_PROD_COUNT:-0}
echo "$INITIAL_PROD_COUNT" > /tmp/initial_activity_productions_count

# --- Record baseline IDs so we can identify NEW records ---
ekylibre_db_query "SELECT id FROM activity_productions ORDER BY id;" \
    > /tmp/initial_activity_production_ids 2>/dev/null || echo "" > /tmp/initial_activity_production_ids

# --- Record campaigns currently in the system ---
ekylibre_db_query "SELECT id, name, started_on FROM campaigns ORDER BY started_on;" \
    > /tmp/existing_campaigns 2>/dev/null || echo "" > /tmp/existing_campaigns

echo "Baseline activity_productions count: $INITIAL_PROD_COUNT"
echo "Existing campaigns:"
cat /tmp/existing_campaigns

# --- Record timestamp AFTER recording baseline ---
date +%s > /tmp/task_start_timestamp_crop_rotation

# --- Navigate Firefox to the Activity Productions page ---
# The agent needs to explore from here — we show the Productions list, not a "new" form,
# so the agent must discover how to create activity productions from existing context.
ensure_firefox_with_ekylibre "${EKYLIBRE_BASE}/backend/activity_productions"
sleep 3
maximize_firefox

take_screenshot /tmp/task_start_screenshot_crop_rotation.png

echo "=== Setup Complete ==="
echo "Baseline productions: $INITIAL_PROD_COUNT"
echo "Agent should review 2023 crop history and plan 2024 rotation for >=3 parcels"
echo "URL: ${EKYLIBRE_BASE}/backend/activity_productions"
