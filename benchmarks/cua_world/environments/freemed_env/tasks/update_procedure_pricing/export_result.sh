#!/bin/bash
# Export script for update_procedure_pricing
# Queries the database for the final prices and exports to JSON

echo "=== Exporting update_procedure_pricing result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve initial state data
INITIAL_COUNT=$(cat /tmp/initial_cpt_count.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Query current CPT count
CURRENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM cpt" 2>/dev/null || echo "0")

# Query prices for 99213 and 99214
PRICE_99213=$(freemed_query "SELECT cptprice FROM cpt WHERE cptcode='99213' LIMIT 1" 2>/dev/null | tr -d '\r' || echo "0.00")
PRICE_99214=$(freemed_query "SELECT cptprice FROM cpt WHERE cptcode='99214' LIMIT 1" 2>/dev/null | tr -d '\r' || echo "0.00")

echo "CPT Count: Initial=$INITIAL_COUNT, Current=$CURRENT_COUNT"
echo "CPT 99213 Final Price: $PRICE_99213"
echo "CPT 99214 Final Price: $PRICE_99214"

# Ensure variables aren't completely empty before JSON writing
PRICE_99213=${PRICE_99213:-"0.00"}
PRICE_99214=${PRICE_99214:-"0.00"}

# Create JSON output
TEMP_JSON=$(mktemp /tmp/update_cpt_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_cpt_count": $INITIAL_COUNT,
    "current_cpt_count": $CURRENT_COUNT,
    "price_99213": "$PRICE_99213",
    "price_99214": "$PRICE_99214",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location securely
rm -f /tmp/update_procedure_pricing_result.json 2>/dev/null || sudo rm -f /tmp/update_procedure_pricing_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/update_procedure_pricing_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/update_procedure_pricing_result.json
chmod 666 /tmp/update_procedure_pricing_result.json 2>/dev/null || sudo chmod 666 /tmp/update_procedure_pricing_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/update_procedure_pricing_result.json"
cat /tmp/update_procedure_pricing_result.json

echo ""
echo "=== Export Complete ==="