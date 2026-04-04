#!/bin/bash
# Task: phytosanitary_spray_campaign
# Export: Count new spraying interventions, check dates and procedure types.

echo "=== Exporting phytosanitary_spray_campaign result ==="

source /workspace/scripts/task_utils.sh

if ! type ekylibre_db_query &>/dev/null; then
    ekylibre_db_query() {
        docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A \
            -c "SET search_path TO demo,lexicon,public; $1" 2>/dev/null || echo ""
    }
fi

take_screenshot /tmp/task_end_screenshot_spray_campaign.png

TASK_START=$(cat /tmp/task_start_timestamp_spray_campaign 2>/dev/null || echo "0")

# --- Count ALL new interventions ---
ALL_NEW=$(ekylibre_db_query "
SELECT COUNT(*) FROM interventions
WHERE EXTRACT(EPOCH FROM created_at)::bigint > $TASK_START;
" | tr -d '[:space:]' || echo "0")
ALL_NEW=${ALL_NEW:-0}

# --- Count spraying-type interventions (pulvérisation / spraying) ---
SPRAY_NEW=$(ekylibre_db_query "
SELECT COUNT(*) FROM interventions
WHERE EXTRACT(EPOCH FROM created_at)::bigint > $TASK_START
  AND (
    procedure_name ILIKE '%spray%'
    OR procedure_name ILIKE '%pulv%'
    OR procedure_name ILIKE '%plant_watering%'
    OR procedure_name ILIKE '%treatment%'
    OR procedure_name ILIKE '%traitement%'
    OR procedure_name ILIKE '%phyto%'
  );
" | tr -d '[:space:]' || echo "0")
SPRAY_NEW=${SPRAY_NEW:-0}

# --- Check dates of new interventions ---
DATED_CORRECTLY=$(ekylibre_db_query "
SELECT COUNT(*) FROM interventions
WHERE EXTRACT(EPOCH FROM created_at)::bigint > $TASK_START
  AND started_at::date = '2023-06-15';
" | tr -d '[:space:]' || echo "0")
DATED_CORRECTLY=${DATED_CORRECTLY:-0}

# --- Check if new interventions have parameters (inputs/tools/workers) ---
INTERVENTIONS_WITH_PARAMS=$(ekylibre_db_query "
SELECT COUNT(DISTINCT i.id) FROM interventions i
JOIN intervention_parameters ip ON ip.intervention_id = i.id
WHERE EXTRACT(EPOCH FROM i.created_at)::bigint > $TASK_START;
" | tr -d '[:space:]' || echo "0")
INTERVENTIONS_WITH_PARAMS=${INTERVENTIONS_WITH_PARAMS:-0}

# --- Get the procedure names of new interventions for feedback ---
PROCEDURE_NAMES=$(ekylibre_db_query "
SELECT DISTINCT procedure_name FROM interventions
WHERE EXTRACT(EPOCH FROM created_at)::bigint > $TASK_START
LIMIT 10;
" 2>/dev/null | tr '\n' ',' || echo "")

# --- Check how many new interventions are linked to wheat parcels ---
# (via intervention_targets or zone_activity_productions)
WHEAT_LINKED=$(ekylibre_db_query "
SELECT COUNT(DISTINCT i.id) FROM interventions i
JOIN intervention_parameters ip ON ip.intervention_id = i.id
JOIN activity_productions ap ON ap.support_id = ip.product_id
WHERE EXTRACT(EPOCH FROM i.created_at)::bigint > $TASK_START
  AND ap.activity_id = 3;
" | tr -d '[:space:]' || echo "0")
WHEAT_LINKED=${WHEAT_LINKED:-0}

cat > /tmp/spray_campaign_result.json << EOF
{
    "task": "phytosanitary_spray_campaign",
    "task_start": $TASK_START,
    "all_new_interventions": $ALL_NEW,
    "new_spraying_interventions": $SPRAY_NEW,
    "interventions_dated_2023_06_15": $DATED_CORRECTLY,
    "interventions_with_parameters": $INTERVENTIONS_WITH_PARAMS,
    "interventions_linked_to_wheat": $WHEAT_LINKED,
    "procedure_names_used": "$(echo "$PROCEDURE_NAMES" | tr '"' "'")"
}
EOF

echo "=== Export Complete ==="
echo "All new interventions: $ALL_NEW"
echo "New spraying interventions: $SPRAY_NEW"
echo "Dated 2023-06-15: $DATED_CORRECTLY"
echo "With parameters: $INTERVENTIONS_WITH_PARAMS"
echo "Linked to wheat parcels: $WHEAT_LINKED"
echo "Procedure names: $PROCEDURE_NAMES"
