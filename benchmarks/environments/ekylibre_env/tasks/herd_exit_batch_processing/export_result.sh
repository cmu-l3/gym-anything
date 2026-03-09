#!/bin/bash
# Task: herd_exit_batch_processing
# Export: Query animals with exits recorded after task start, and new sale invoices.

echo "=== Exporting herd_exit_batch_processing result ==="

source /workspace/scripts/task_utils.sh

if ! type ekylibre_db_query &>/dev/null; then
    ekylibre_db_query() {
        docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A \
            -c "SET search_path TO demo,lexicon,public; $1" 2>/dev/null || echo ""
    }
fi

take_screenshot /tmp/task_end_screenshot_herd_exit.png

TASK_START=$(cat /tmp/task_start_timestamp_herd_exit 2>/dev/null || echo "0")

# --- Count animals with exit recorded after task_start ---
# Check animals table first
EXITS_AFTER=$(ekylibre_db_query "
SELECT COUNT(*) FROM animals
WHERE exit_at IS NOT NULL
  AND EXTRACT(EPOCH FROM updated_at)::bigint > $TASK_START;
" | tr -d '[:space:]' || echo "0")
EXITS_AFTER=${EXITS_AFTER:-0}

# --- Check the exit date value ---
EXITS_ON_TARGET_DATE=$(ekylibre_db_query "
SELECT COUNT(*) FROM animals
WHERE exit_at IS NOT NULL
  AND exit_at::date = '2024-03-01'
  AND EXTRACT(EPOCH FROM updated_at)::bigint > $TASK_START;
" | tr -d '[:space:]' || echo "0")
EXITS_ON_TARGET_DATE=${EXITS_ON_TARGET_DATE:-0}

# --- Get details of exited animals for born_at check ---
EXITED_ANIMALS=$(ekylibre_db_query "
SELECT id, name, born_at, exit_at
FROM animals
WHERE exit_at IS NOT NULL
  AND EXTRACT(EPOCH FROM updated_at)::bigint > $TASK_START
ORDER BY born_at ASC
LIMIT 10;
" 2>/dev/null || echo "")

# --- Check if exited animals are among oldest (born before 2010) ---
OLDEST_EXITED=$(ekylibre_db_query "
SELECT COUNT(*) FROM animals
WHERE exit_at IS NOT NULL
  AND EXTRACT(EPOCH FROM updated_at)::bigint > $TASK_START
  AND born_at < '2010-01-01';
" | tr -d '[:space:]' || echo "0")
OLDEST_EXITED=${OLDEST_EXITED:-0}

# --- Count new sale invoices ---
NEW_SALES=$(ekylibre_db_query "
SELECT COUNT(*) FROM sale_invoices
WHERE EXTRACT(EPOCH FROM created_at)::bigint > $TASK_START;
" | tr -d '[:space:]' || echo "0")
NEW_SALES=${NEW_SALES:-0}

# --- Get new sale invoice details ---
SALE_DETAILS=$(ekylibre_db_query "
SELECT id, number, invoiced_at, state, amount
FROM sale_invoices
WHERE EXTRACT(EPOCH FROM created_at)::bigint > $TASK_START
ORDER BY id DESC LIMIT 5;
" 2>/dev/null || echo "")

cat > /tmp/herd_exit_result.json << EOF
{
    "task": "herd_exit_batch_processing",
    "task_start": $TASK_START,
    "animals_exited_after_start": $EXITS_AFTER,
    "exits_on_target_date_2024_03_01": $EXITS_ON_TARGET_DATE,
    "oldest_animals_exited": $OLDEST_EXITED,
    "new_sale_invoices": $NEW_SALES,
    "sale_details": "$(echo "$SALE_DETAILS" | tr '"' "'" | tr '\n' ';')",
    "exited_animal_details": "$(echo "$EXITED_ANIMALS" | tr '"' "'" | tr '\n' ';')"
}
EOF

echo "=== Export Complete ==="
echo "Animals exited after task start: $EXITS_AFTER"
echo "Exits on 2024-03-01: $EXITS_ON_TARGET_DATE"
echo "Oldest animals exited (born<2010): $OLDEST_EXITED"
echo "New sale invoices: $NEW_SALES"
