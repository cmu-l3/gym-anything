#!/bin/bash
# Export script for Configure Email Settings task

echo "=== Exporting Configure Email Settings Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# List of options to verify
OPTIONS=(
    "woocommerce_email_from_name"
    "woocommerce_email_from_address"
    "woocommerce_email_header_image"
    "woocommerce_email_footer_text"
    "woocommerce_email_base_color"
    "woocommerce_email_background_color"
    "woocommerce_email_body_background_color"
    "woocommerce_email_text_color"
)

# Build JSON result
# We will verify values in the python verifier, so we just dump the DB state here
JSON_CONTENT="{"
JSON_CONTENT="$JSON_CONTENT \"timestamp\": \"$(date -Iseconds)\","

# Add Final Values
JSON_CONTENT="$JSON_CONTENT \"final_values\": {"
FIRST=true
for opt in "${OPTIONS[@]}"; do
    VAL=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='$opt' LIMIT 1" 2>/dev/null)
    VAL_ESC=$(json_escape "$VAL")
    
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        JSON_CONTENT="$JSON_CONTENT,"
    fi
    JSON_CONTENT="$JSON_CONTENT \"$opt\": \"$VAL_ESC\""
done
JSON_CONTENT="$JSON_CONTENT },"

# Add Initial Values (read from setup file)
INITIAL_JSON=$(cat /tmp/initial_email_settings.json 2>/dev/null || echo "{}")
JSON_CONTENT="$JSON_CONTENT \"initial_values\": $INITIAL_JSON"

JSON_CONTENT="$JSON_CONTENT }"

# Write to result file
safe_write_json "$JSON_CONTENT" /tmp/task_result.json

echo ""
echo "Result JSON preview:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="