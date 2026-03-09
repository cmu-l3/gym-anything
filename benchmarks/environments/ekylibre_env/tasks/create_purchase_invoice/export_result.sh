#!/bin/bash
echo "=== Exporting create_purchase_invoice results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_invoice_count.txt 2>/dev/null || echo "0")

# Get current count
CURRENT_COUNT=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c "SELECT COUNT(*) FROM purchases WHERE type = 'PurchaseInvoice';" 2>/dev/null || echo "0")

# 1. Search for the specific invoice by Reference Number (Primary Success Indicator)
# We return JSON directly from Postgres
TARGET_INVOICE_JSON=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c "
    SELECT row_to_json(t) FROM (
        SELECT 
            p.id, 
            p.reference_number, 
            p.invoiced_at, 
            p.pretax_amount, 
            p.amount, 
            p.created_at,
            e.full_name as supplier_name,
            (SELECT COUNT(*) FROM purchase_items pi WHERE pi.purchase_id = p.id) as item_count
        FROM purchases p
        LEFT JOIN entities e ON p.supplier_id = e.id
        WHERE p.type = 'PurchaseInvoice' 
        AND p.reference_number ILIKE '%INV-2024-0587%'
        LIMIT 1
    ) t;
" 2>/dev/null || echo "null")

# 2. If target not found, find the most recent invoice created during the task (Fallback for partial credit)
if [ "$TARGET_INVOICE_JSON" == "null" ] || [ -z "$TARGET_INVOICE_JSON" ]; then
    echo "Target reference not found, looking for any recent invoice..."
    RECENT_INVOICE_JSON=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c "
        SELECT row_to_json(t) FROM (
            SELECT 
                p.id, 
                p.reference_number, 
                p.invoiced_at, 
                p.pretax_amount, 
                p.amount, 
                p.created_at,
                e.full_name as supplier_name,
                (SELECT COUNT(*) FROM purchase_items pi WHERE pi.purchase_id = p.id) as item_count
            FROM purchases p
            LEFT JOIN entities e ON p.supplier_id = e.id
            WHERE p.type = 'PurchaseInvoice' 
            AND p.created_at > to_timestamp($TASK_START)
            ORDER BY p.created_at DESC
            LIMIT 1
        ) t;
    " 2>/dev/null || echo "null")
    
    # Use the recent invoice, but mark that reference didn't match logic later
    INVOICE_DATA="$RECENT_INVOICE_JSON"
else
    INVOICE_DATA="$TARGET_INVOICE_JSON"
fi

# Default to null if still empty
if [ -z "$INVOICE_DATA" ]; then INVOICE_DATA="null"; fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "invoice_data": $INVOICE_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="