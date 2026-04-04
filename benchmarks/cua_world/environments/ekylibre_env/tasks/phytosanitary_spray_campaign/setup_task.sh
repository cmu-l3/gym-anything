#!/bin/bash
# Task: phytosanitary_spray_campaign
# Setup: Record baseline interventions count; capture wheat parcel reference data;
# navigate to interventions list as starting point.

echo "=== Setting up phytosanitary_spray_campaign ==="

source /workspace/scripts/task_utils.sh

if ! type ekylibre_db_query &>/dev/null; then
    ekylibre_db_query() {
        docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A \
            -c "SET search_path TO demo,lexicon,public; $1" 2>/dev/null || echo ""
    }
fi

wait_for_ekylibre 120
EKYLIBRE_BASE=$(detect_ekylibre_url)

# --- Record baseline intervention count ---
INITIAL_INTERVENTIONS=$(ekylibre_db_query "SELECT COUNT(*) FROM interventions;" \
    | tr -d '[:space:]' || echo "0")
INITIAL_INTERVENTIONS=${INITIAL_INTERVENTIONS:-0}
echo "$INITIAL_INTERVENTIONS" > /tmp/initial_interventions_count

# --- Record current intervention IDs ---
ekylibre_db_query "SELECT id FROM interventions ORDER BY id;" \
    > /tmp/initial_intervention_ids 2>/dev/null || echo "" > /tmp/initial_intervention_ids

# --- Record wheat parcels for reference (activity_id=3 = Blé tendre d'hiver, campaign_id=8 = 2023) ---
WHEAT_PARCEL_COUNT=$(ekylibre_db_query "
SELECT COUNT(*) FROM activity_productions
WHERE activity_id = 3 AND campaign_id = 8 AND support_id IS NOT NULL;
" | tr -d '[:space:]' || echo "0")
WHEAT_PARCEL_COUNT=${WHEAT_PARCEL_COUNT:-0}

ekylibre_db_query "
SELECT ap.id, ap.support_id, lp.name AS parcel_name
FROM activity_productions ap
LEFT JOIN land_parcels lp ON lp.id = ap.support_id
WHERE ap.activity_id = 3 AND ap.campaign_id = 8
ORDER BY ap.id;
" > /tmp/wheat_parcels_reference 2>/dev/null || echo "" > /tmp/wheat_parcels_reference

echo "Wheat parcels (Blé tendre, 2023 campaign): $WHEAT_PARCEL_COUNT"
cat /tmp/wheat_parcels_reference

# --- Record timestamp ---
date +%s > /tmp/task_start_timestamp_spray_campaign

# --- Navigate to interventions page ---
ensure_firefox_with_ekylibre "${EKYLIBRE_BASE}/backend/interventions"
sleep 3
maximize_firefox

take_screenshot /tmp/task_start_screenshot_spray_campaign.png

echo "=== Setup Complete ==="
echo "Baseline interventions: $INITIAL_INTERVENTIONS"
echo "Wheat parcels in 2023 campaign: $WHEAT_PARCEL_COUNT"
echo "Agent should find wheat parcels and create a spraying intervention per parcel"
echo "URL: ${EKYLIBRE_BASE}/backend/interventions"
