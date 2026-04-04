#!/bin/bash
# Task: crop_rotation_plan_for_compliance
# Export: Query new activity_productions created after task start.

echo "=== Exporting crop_rotation_plan_for_compliance result ==="

source /workspace/scripts/task_utils.sh

if ! type ekylibre_db_query &>/dev/null; then
    ekylibre_db_query() {
        local query="$1"
        docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A \
            -c "SET search_path TO demo,lexicon,public; $query" 2>/dev/null || echo ""
    }
fi

take_screenshot /tmp/task_end_screenshot_crop_rotation.png

TASK_START=$(cat /tmp/task_start_timestamp_crop_rotation 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_activity_productions_count 2>/dev/null || echo "0")

# --- Query new activity_productions created after task start ---
NEW_PRODUCTIONS=$(ekylibre_db_query "
SELECT
    ap.id,
    ap.activity_id,
    ap.campaign_id,
    ap.support_id,
    ap.started_on,
    ap.stopped_on,
    COALESCE(a.name, '') AS activity_name,
    COALESCE(c.name, '') AS campaign_name,
    EXTRACT(YEAR FROM c.started_on)::int AS campaign_year,
    EXTRACT(EPOCH FROM ap.created_at)::bigint AS created_epoch
FROM activity_productions ap
LEFT JOIN activities a ON a.id = ap.activity_id
LEFT JOIN campaigns c ON c.id = ap.campaign_id
WHERE EXTRACT(EPOCH FROM ap.created_at)::bigint > $TASK_START
ORDER BY ap.id;
")

# --- Count new records ---
NEW_COUNT=$(echo "$NEW_PRODUCTIONS" | grep -c '|' 2>/dev/null || echo "0")
[ -z "$NEW_PRODUCTIONS" ] && NEW_COUNT=0

# --- Get distinct activity IDs among new productions ---
DISTINCT_ACTIVITIES=$(ekylibre_db_query "
SELECT COUNT(DISTINCT activity_id)
FROM activity_productions
WHERE EXTRACT(EPOCH FROM created_at)::bigint > $TASK_START
  AND activity_id IS NOT NULL;
" | tr -d '[:space:]' || echo "0")
DISTINCT_ACTIVITIES=${DISTINCT_ACTIVITIES:-0}

# --- Check if any have a campaign year of 2024 ---
PRODS_IN_2024=$(ekylibre_db_query "
SELECT COUNT(*)
FROM activity_productions ap
JOIN campaigns c ON c.id = ap.campaign_id
WHERE EXTRACT(EPOCH FROM ap.created_at)::bigint > $TASK_START
  AND EXTRACT(YEAR FROM c.started_on)::int = 2024;
" | tr -d '[:space:]' || echo "0")
PRODS_IN_2024=${PRODS_IN_2024:-0}

# --- Check supports (land parcels) assigned ---
PRODS_WITH_SUPPORT=$(ekylibre_db_query "
SELECT COUNT(*)
FROM activity_productions
WHERE EXTRACT(EPOCH FROM created_at)::bigint > $TASK_START
  AND support_id IS NOT NULL;
" | tr -d '[:space:]' || echo "0")
PRODS_WITH_SUPPORT=${PRODS_WITH_SUPPORT:-0}

# --- Serialize new productions as escaped JSON-safe lines ---
PRODS_JSON="[]"
if [ -n "$NEW_PRODUCTIONS" ]; then
    PRODS_JSON=$(python3 -c "
import sys
lines = '''$NEW_PRODUCTIONS'''.strip().splitlines()
items = []
for l in lines:
    parts = l.split('|')
    if len(parts) >= 9:
        try:
            items.append({
                'id': int(parts[0].strip()),
                'activity_id': parts[1].strip(),
                'campaign_id': parts[2].strip(),
                'support_id': parts[3].strip(),
                'started_on': parts[4].strip(),
                'stopped_on': parts[5].strip(),
                'activity_name': parts[6].strip(),
                'campaign_name': parts[7].strip(),
                'campaign_year': int(parts[8].strip()) if parts[8].strip().lstrip('-').isdigit() else 0,
            })
        except Exception:
            pass
import json
print(json.dumps(items))
" 2>/dev/null || echo "[]")
fi

cat > /tmp/crop_rotation_result.json << EOF
{
    "task": "crop_rotation_plan_for_compliance",
    "task_start": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "new_productions_count": $NEW_COUNT,
    "distinct_activities_count": $DISTINCT_ACTIVITIES,
    "productions_in_2024_campaign": $PRODS_IN_2024,
    "productions_with_support": $PRODS_WITH_SUPPORT,
    "new_productions": $PRODS_JSON
}
EOF

echo "=== Export Complete ==="
echo "New activity productions: $NEW_COUNT"
echo "Distinct activities used: $DISTINCT_ACTIVITIES"
echo "Productions in 2024 campaign: $PRODS_IN_2024"
echo "Productions with support assigned: $PRODS_WITH_SUPPORT"
