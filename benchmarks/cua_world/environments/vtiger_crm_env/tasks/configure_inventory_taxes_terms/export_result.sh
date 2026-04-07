#!/bin/bash
echo "=== Exporting configure_inventory_taxes_terms results ==="

source /workspace/scripts/task_utils.sh

# Record end state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query DB for Product Taxes (GST, PST)
GST_PERCENT=$(vtiger_db_query "SELECT percentage FROM vtiger_inventorytaxinfo WHERE taxlabel='GST' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
PST_PERCENT=$(vtiger_db_query "SELECT percentage FROM vtiger_inventorytaxinfo WHERE taxlabel='PST' AND deleted=0 LIMIT 1" | tr -d '[:space:]')

# 2. Query DB for Shipping Taxes (Shipping GST)
SHIPPING_GST_PERCENT=$(vtiger_db_query "SELECT percentage FROM vtiger_shippingtaxinfo WHERE taxlabel='Shipping GST' AND deleted=0 LIMIT 1" | tr -d '[:space:]')

# 3. Query DB for Terms and Conditions Text
TANDC_TEXT=$(vtiger_db_query "SELECT tandc FROM vtiger_inventory_tandc LIMIT 1")

# 4. Compile into JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "gst_percent": "$(json_escape "${GST_PERCENT:-}")",
  "pst_percent": "$(json_escape "${PST_PERCENT:-}")",
  "shipping_gst_percent": "$(json_escape "${SHIPPING_GST_PERCENT:-}")",
  "tandc_text": "$(json_escape "${TANDC_TEXT:-}")"
}
EOF

# 5. Export safely
safe_write_result "/tmp/task_result.json" "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="