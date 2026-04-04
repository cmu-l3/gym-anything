#!/bin/bash
# Export script for Create Product API Endpoint task
echo "=== Exporting Create Product API Endpoint Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check if modules are enabled
echo "Checking enabled modules..."
MODULES_ENABLED="false"
if $DRUSH pm:list --status=enabled | grep -q "rest"; then
    if $DRUSH pm:list --status=enabled | grep -q "serialization"; then
        MODULES_ENABLED="true"
    fi
fi

# 2. Check if View exists
echo "Checking View configuration..."
VIEW_EXISTS="false"
VIEW_CONFIG=""
if $DRUSH config:get views.view.product_api > /tmp/view_config.yml 2>/dev/null; then
    VIEW_EXISTS="true"
    VIEW_CONFIG=$(cat /tmp/view_config.yml)
    echo "View 'product_api' found."
elif $DRUSH config:list | grep -q "views.view"; then
    # Try to find any view with the right path if name is different
    # This is a bit complex in bash, so we mostly rely on the endpoint check
    echo "Specific view name not found, checking endpoint..."
fi

# 3. Test the Endpoint (Local curl)
echo "Testing API endpoint..."
ENDPOINT_URL="http://localhost/api/v1/products"
RESPONSE_FILE="/tmp/api_response.json"
HEADERS_FILE="/tmp/api_headers.txt"

# Curl with -i to include headers, follow redirects (-L), max time 10s
# We do NOT provide auth credentials to test public access
curl -v -s -L --max-time 10 "$ENDPOINT_URL" > "$RESPONSE_FILE" 2> "$HEADERS_FILE"

HTTP_STATUS=$(grep "< HTTP/" "$HEADERS_FILE" | tail -1 | awk '{print $3}')
CONTENT_TYPE=$(grep "< Content-Type:" "$HEADERS_FILE" | tail -1 | cut -d':' -f2 | tr -d ' \r\n')

echo "HTTP Status: $HTTP_STATUS"
echo "Content Type: $CONTENT_TYPE"

# Simple validation of JSON validity
IS_VALID_JSON="false"
if [ -s "$RESPONSE_FILE" ]; then
    if jq -e . "$RESPONSE_FILE" >/dev/null 2>&1; then
        IS_VALID_JSON="true"
    fi
fi

# 4. Export detailed view config for verifier to inspect access settings if needed
# We look for the display that has our path
PATH_CHECK=$($DRUSH php:eval '
use Drupal\views\Views;
$view = Views::getView("product_api");
if (!$view) {
    // Try to iterate all views to find one with the path
    $views = \Drupal\views\Entity\View::loadMultiple();
    foreach ($views as $v) {
        $executable = \Drupal\views\Views::getView($v->id());
        $executable->initDisplay();
        foreach ($executable->displayHandlers as $display) {
            if ($display->hasPath() && $display->getPath() == "api/v1/products") {
                echo "FOUND:" . $v->id();
                exit;
            }
        }
    }
    echo "NOT_FOUND";
} else {
    echo "FOUND:product_api";
}
')

VIEW_FOUND_ID=$(echo "$PATH_CHECK" | cut -d':' -f2)
if [ "$PATH_CHECK" == "NOT_FOUND" ]; then
    VIEW_FOUND_ID=""
fi

# Create result JSON
# We embed the first 2KB of the API response to avoid huge files
API_RESPONSE_SAMPLE=""
if [ "$IS_VALID_JSON" = "true" ]; then
    API_RESPONSE_SAMPLE=$(cat "$RESPONSE_FILE" | head -c 5000)
fi

create_result_json /tmp/task_result.json \
    "modules_enabled=$MODULES_ENABLED" \
    "view_exists=$VIEW_EXISTS" \
    "view_found_id=$VIEW_FOUND_ID" \
    "http_status=${HTTP_STATUS:-0}" \
    "content_type=$(json_escape "$CONTENT_TYPE")" \
    "is_valid_json=$IS_VALID_JSON" \
    "api_response_sample=$(json_escape "$API_RESPONSE_SAMPLE")"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated."
echo "=== Export Complete ==="