#!/bin/bash
# Export script for Configure Apparel Tax Class task

echo "=== Exporting Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify DB connection
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Tax Classes Configuration
# WooCommerce stores additional tax classes in 'woocommerce_tax_classes' option (newline separated)
FINAL_TAX_CLASSES=$(wc_query "SELECT option_value FROM wp_options WHERE option_name = 'woocommerce_tax_classes'" 2>/dev/null)
INITIAL_TAX_CLASSES=$(cat /tmp/initial_tax_classes.txt 2>/dev/null || echo "")

# 3. Get Tax Rates
# We look for a rate with class 'apparel' (slugified), country US, state NY
# Note: Custom tax classes are stored as slugs in the tax_rate_class column (e.g., 'apparel')
TAX_RATE_DATA=$(wc_query "SELECT tax_rate_id, tax_rate, tax_rate_name, tax_rate_priority, tax_rate_shipping 
    FROM wp_woocommerce_tax_rates 
    WHERE tax_rate_class = 'apparel' 
    AND tax_rate_country = 'US' 
    AND tax_rate_state = 'NY' 
    LIMIT 1" 2>/dev/null)

RATE_FOUND="false"
RATE_VALUE=""
RATE_NAME=""
RATE_SHIPPING=""

if [ -n "$TAX_RATE_DATA" ]; then
    RATE_FOUND="true"
    RATE_VALUE=$(echo "$TAX_RATE_DATA" | cut -f2)
    RATE_NAME=$(echo "$TAX_RATE_DATA" | cut -f3)
    RATE_SHIPPING=$(echo "$TAX_RATE_DATA" | cut -f5)
fi

# 4. Get Product Tax Class Assignment
TARGET_PRODUCT_ID=$(cat /tmp/target_product_id.txt 2>/dev/null)
PRODUCT_ASSIGNMENT_CORRECT="false"
ACTUAL_PRODUCT_TAX_CLASS=""

if [ -n "$TARGET_PRODUCT_ID" ]; then
    # WooCommerce stores the selected tax class in '_tax_class' meta key
    # For standard, it's empty. For custom, it's the slug (e.g., 'apparel')
    ACTUAL_PRODUCT_TAX_CLASS=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$TARGET_PRODUCT_ID AND meta_key='_tax_class' LIMIT 1" 2>/dev/null)
    
    if [ "$ACTUAL_PRODUCT_TAX_CLASS" == "apparel" ]; then
        PRODUCT_ASSIGNMENT_CORRECT="true"
    fi
fi

# 5. Check if initial classes were preserved
# Logic: If initial was not empty, it should still be present in final string
PRESERVED_EXISTING="true"
if [ -n "$INITIAL_TAX_CLASSES" ]; then
    if [[ "$FINAL_TAX_CLASSES" != *"$INITIAL_TAX_CLASSES"* ]]; then
        # Check if maybe they just re-ordered them or added to it.
        # Simple check: line count shouldn't decrease significantly
        PRESERVED_EXISTING="false"
        # Let verify.py handle loose matching if needed, but for bash we flag exact containment
    fi
fi

# Escape strings for JSON
FINAL_TAX_CLASSES_ESC=$(json_escape "$FINAL_TAX_CLASSES")
RATE_NAME_ESC=$(json_escape "$RATE_NAME")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "final_tax_classes": "$FINAL_TAX_CLASSES_ESC",
    "rate_found": $RATE_FOUND,
    "rate_value": "$RATE_VALUE",
    "rate_name": "$RATE_NAME_ESC",
    "rate_shipping": "$RATE_SHIPPING",
    "product_id": "$TARGET_PRODUCT_ID",
    "product_tax_class": "$ACTUAL_PRODUCT_TAX_CLASS",
    "product_assignment_correct": $PRODUCT_ASSIGNMENT_CORRECT,
    "initial_tax_classes_preserved": $PRESERVED_EXISTING,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json
echo "=== Export Complete ==="
cat /tmp/task_result.json