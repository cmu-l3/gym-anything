#!/bin/bash
# Task: herd_exit_batch_processing
# Setup: Record baseline animal exit state; navigate to animals list.

echo "=== Setting up herd_exit_batch_processing ==="

source /workspace/scripts/task_utils.sh

if ! type ekylibre_db_query &>/dev/null; then
    ekylibre_db_query() {
        docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A \
            -c "SET search_path TO demo,lexicon,public; $1" 2>/dev/null || echo ""
    }
fi

wait_for_ekylibre 120
EKYLIBRE_BASE=$(detect_ekylibre_url)

# --- Record baseline: how many animals already have an exit recorded ---
# Ekylibre stores animals in the 'products' table with born_at/dead_at columns
# AND/OR in a separate 'animals' table. Try both.
INITIAL_EXITS=$(ekylibre_db_query "
SELECT COUNT(*) FROM (
    SELECT id FROM animals WHERE exit_at IS NOT NULL
    UNION ALL
    SELECT id FROM products WHERE type ILIKE '%animal%' AND dead_at IS NOT NULL
) t;
" | tr -d '[:space:]' || echo "0")
INITIAL_EXITS=${INITIAL_EXITS:-0}
echo "$INITIAL_EXITS" > /tmp/initial_animal_exits_count

# --- Record baseline sale invoice count ---
INITIAL_SALES=$(ekylibre_db_query "SELECT COUNT(*) FROM sale_invoices;" | tr -d '[:space:]' || echo "0")
INITIAL_SALES=${INITIAL_SALES:-0}
echo "$INITIAL_SALES" > /tmp/initial_sale_invoices_count

# --- Record the 5 oldest animal IDs for reference ---
ekylibre_db_query "
SELECT id, name, born_at FROM animals
WHERE born_at IS NOT NULL AND exit_at IS NULL
ORDER BY born_at ASC
LIMIT 5;
" > /tmp/oldest_animals_reference 2>/dev/null || \
ekylibre_db_query "
SELECT id, name, born_at FROM products
WHERE type ILIKE '%animal%' AND born_at IS NOT NULL AND dead_at IS NULL
ORDER BY born_at ASC
LIMIT 5;
" > /tmp/oldest_animals_reference 2>/dev/null || \
echo "" > /tmp/oldest_animals_reference

echo "Oldest 5 animals (reference for verifier):"
cat /tmp/oldest_animals_reference

# --- Record timestamp ---
date +%s > /tmp/task_start_timestamp_herd_exit

# --- Navigate to animals list ---
ensure_firefox_with_ekylibre "${EKYLIBRE_BASE}/backend/animals"
sleep 3
maximize_firefox

take_screenshot /tmp/task_start_screenshot_herd_exit.png

echo "=== Setup Complete ==="
echo "Baseline animal exits: $INITIAL_EXITS"
echo "Baseline sale invoices: $INITIAL_SALES"
echo "Agent should find 5 oldest animals and record their exit (Abattage, 2024-03-01)"
echo "Then create a consolidated sale invoice for the 5 animals"
