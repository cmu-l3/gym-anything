#!/bin/bash
# Export script for Import Tax Rates CSV task

echo "=== Exporting Import Tax Rates Result ==="

source /workspace/scripts/task_utils.sh

# Verify DB connection
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get counts
INITIAL_COUNT=$(cat /tmp/initial_tax_count 2>/dev/null || echo "0")
FINAL_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_woocommerce_tax_rates" 2>/dev/null || echo "0")

echo "Tax rates: Initial=$INITIAL_COUNT, Final=$FINAL_COUNT"

# 2. Check specific data integrity
# Check Seattle (98101)
SEATTLE_CHECK=$(wc_query "SELECT tax_rate 
    FROM wp_woocommerce_tax_rates tr
    JOIN wp_woocommerce_tax_rate_locations trl ON tr.tax_rate_id = trl.tax_rate_id
    WHERE trl.location_code = '98101' AND trl.location_type = 'postcode' 
    LIMIT 1" 2>/dev/null)

# Check Spokane (99201)
SPOKANE_CHECK=$(wc_query "SELECT tax_rate 
    FROM wp_woocommerce_tax_rates tr
    JOIN wp_woocommerce_tax_rate_locations trl ON tr.tax_rate_id = trl.tax_rate_id
    WHERE trl.location_code = '99201' AND trl.location_type = 'postcode' 
    LIMIT 1" 2>/dev/null)

# Check Tax Name consistency
NAME_CHECK=$(wc_query "SELECT DISTINCT tax_rate_name FROM wp_woocommerce_tax_rates WHERE tax_rate_name = 'WA Sales Tax'" 2>/dev/null)

# 3. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": ${INITIAL_COUNT:-0},
    "final_count": ${FINAL_COUNT:-0},
    "seattle_rate_found": "$( [ -n "$SEATTLE_CHECK" ] && echo "true" || echo "false" )",
    "seattle_rate_value": "${SEATTLE_CHECK:-0}",
    "spokane_rate_found": "$( [ -n "$SPOKANE_CHECK" ] && echo "true" || echo "false" )",
    "spokane_rate_value": "${SPOKANE_CHECK:-0}",
    "tax_name_correct": "$( [ "$NAME_CHECK" = "WA Sales Tax" ] && echo "true" || echo "false" )",
    "csv_file_exists": "$( [ -f /home/ga/Documents/wa_tax_rates.csv ] && echo "true" || echo "false" )",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export Complete ==="