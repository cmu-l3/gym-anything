#!/bin/bash
# Task: purchase_invoice_multi_supplier_entry
# Setup: Record baseline purchase invoice count; navigate to entities list.

echo "=== Setting up purchase_invoice_multi_supplier_entry ==="

source /workspace/scripts/task_utils.sh

if ! type ekylibre_db_query &>/dev/null; then
    ekylibre_db_query() {
        docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A \
            -c "SET search_path TO demo,lexicon,public; $1" 2>/dev/null || echo ""
    }
fi

wait_for_ekylibre 120
EKYLIBRE_BASE=$(detect_ekylibre_url)

# --- Record baseline purchase invoice count ---
INITIAL_INVOICES=$(ekylibre_db_query "SELECT COUNT(*) FROM purchase_invoices;" \
    | tr -d '[:space:]' || echo "0")
INITIAL_INVOICES=${INITIAL_INVOICES:-0}
echo "$INITIAL_INVOICES" > /tmp/initial_purchase_invoices_count

# --- Record baseline supplier entities ---
SUPPLIER_COUNT=$(ekylibre_db_query "
SELECT COUNT(*) FROM entities WHERE supplier_account_id IS NOT NULL;
" | tr -d '[:space:]' || echo "0")
SUPPLIER_COUNT=${SUPPLIER_COUNT:-0}
echo "Supplier entities in system: $SUPPLIER_COUNT"

# --- List a sample of suppliers for reference ---
ekylibre_db_query "
SELECT id, full_name FROM entities
WHERE supplier_account_id IS NOT NULL
ORDER BY id
LIMIT 10;
" > /tmp/sample_suppliers 2>/dev/null || echo "" > /tmp/sample_suppliers

echo "Sample suppliers:"
cat /tmp/sample_suppliers

# --- Record timestamp ---
date +%s > /tmp/task_start_timestamp_purchase_entry

# --- Navigate to entities list (agent must discover suppliers from there) ---
ensure_firefox_with_ekylibre "${EKYLIBRE_BASE}/backend/entities"
sleep 3
maximize_firefox

take_screenshot /tmp/task_start_screenshot_purchase_entry.png

echo "=== Setup Complete ==="
echo "Baseline purchase invoices: $INITIAL_INVOICES"
echo "Agent should find 3 suppliers and create one invoice per supplier"
echo "URL: ${EKYLIBRE_BASE}/backend/entities"
