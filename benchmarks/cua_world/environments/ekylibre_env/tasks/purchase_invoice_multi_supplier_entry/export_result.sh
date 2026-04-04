#!/bin/bash
# Task: purchase_invoice_multi_supplier_entry
# Export: Count new purchase invoices, check suppliers and validation state.

echo "=== Exporting purchase_invoice_multi_supplier_entry result ==="

source /workspace/scripts/task_utils.sh

if ! type ekylibre_db_query &>/dev/null; then
    ekylibre_db_query() {
        docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A \
            -c "SET search_path TO demo,lexicon,public; $1" 2>/dev/null || echo ""
    }
fi

take_screenshot /tmp/task_end_screenshot_purchase_entry.png

TASK_START=$(cat /tmp/task_start_timestamp_purchase_entry 2>/dev/null || echo "0")

# --- Count new purchase invoices ---
NEW_INVOICES=$(ekylibre_db_query "
SELECT COUNT(*) FROM purchase_invoices
WHERE EXTRACT(EPOCH FROM created_at)::bigint > $TASK_START;
" | tr -d '[:space:]' || echo "0")
NEW_INVOICES=${NEW_INVOICES:-0}

# --- Count distinct suppliers ---
DISTINCT_SUPPLIERS=$(ekylibre_db_query "
SELECT COUNT(DISTINCT supplier_id) FROM purchase_invoices
WHERE EXTRACT(EPOCH FROM created_at)::bigint > $TASK_START
  AND supplier_id IS NOT NULL;
" | tr -d '[:space:]' || echo "0")
DISTINCT_SUPPLIERS=${DISTINCT_SUPPLIERS:-0}

# --- Count validated invoices ---
VALIDATED=$(ekylibre_db_query "
SELECT COUNT(*) FROM purchase_invoices
WHERE EXTRACT(EPOCH FROM created_at)::bigint > $TASK_START
  AND state IN ('confirmed', 'validated', 'invoice', 'order');
" | tr -d '[:space:]' || echo "0")
VALIDATED=${VALIDATED:-0}

# --- Check invoice dates ---
DATED_CORRECTLY=$(ekylibre_db_query "
SELECT COUNT(*) FROM purchase_invoices
WHERE EXTRACT(EPOCH FROM created_at)::bigint > $TASK_START
  AND invoiced_at::date = '2024-01-20';
" | tr -d '[:space:]' || echo "0")
DATED_CORRECTLY=${DATED_CORRECTLY:-0}

# --- Get invoice details ---
INVOICE_DETAILS=$(ekylibre_db_query "
SELECT pi.id, pi.number, pi.invoiced_at, pi.state,
       COALESCE(pi.amount, 0) AS amount,
       COALESCE(e.full_name, 'unknown') AS supplier_name
FROM purchase_invoices pi
LEFT JOIN entities e ON e.id = pi.supplier_id
WHERE EXTRACT(EPOCH FROM pi.created_at)::bigint > $TASK_START
ORDER BY pi.id DESC LIMIT 10;
" 2>/dev/null || echo "")

# --- Check if journal entries were created (after invoice validation) ---
NEW_JOURNAL_ENTRIES=$(ekylibre_db_query "
SELECT COUNT(*) FROM journal_entries
WHERE EXTRACT(EPOCH FROM created_at)::bigint > $TASK_START;
" | tr -d '[:space:]' || echo "0")
NEW_JOURNAL_ENTRIES=${NEW_JOURNAL_ENTRIES:-0}

cat > /tmp/purchase_entry_result.json << EOF
{
    "task": "purchase_invoice_multi_supplier_entry",
    "task_start": $TASK_START,
    "new_purchase_invoices": $NEW_INVOICES,
    "distinct_suppliers": $DISTINCT_SUPPLIERS,
    "validated_invoices": $VALIDATED,
    "invoices_dated_correctly": $DATED_CORRECTLY,
    "new_journal_entries": $NEW_JOURNAL_ENTRIES,
    "invoice_details": "$(echo "$INVOICE_DETAILS" | tr '"' "'" | tr '\n' ';')"
}
EOF

echo "=== Export Complete ==="
echo "New purchase invoices: $NEW_INVOICES"
echo "Distinct suppliers: $DISTINCT_SUPPLIERS"
echo "Validated invoices: $VALIDATED"
echo "Correctly dated (2024-01-20): $DATED_CORRECTLY"
echo "New journal entries generated: $NEW_JOURNAL_ENTRIES"
