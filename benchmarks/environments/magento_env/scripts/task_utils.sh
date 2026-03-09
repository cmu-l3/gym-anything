#!/bin/bash
# Shared utilities for Magento task setup and export scripts

# =============================================================================
# Database Utilities
# =============================================================================

# Execute SQL query against Magento database (via Docker)
# Args: $1 - SQL query
# Returns: query result (tab-separated, no column headers)
magento_query() {
    local query="$1"
    docker exec magento-mariadb mysql -u magento -pmagentopass magento -N -B -e "$query" 2>/dev/null
}

# Execute SQL query with column headers
magento_query_headers() {
    local query="$1"
    docker exec magento-mariadb mysql -u magento -pmagentopass magento -e "$query" 2>/dev/null
}

# Get total product count
get_product_count() {
    magento_query "SELECT COUNT(*) FROM catalog_product_entity"
}

# Get total category count
get_category_count() {
    magento_query "SELECT COUNT(*) FROM catalog_category_entity"
}

# Get total customer count
get_customer_count() {
    magento_query "SELECT COUNT(*) FROM customer_entity"
}

# Get total order count
get_order_count() {
    magento_query "SELECT COUNT(*) FROM sales_order"
}

# Get product by SKU (case-insensitive)
# Args: $1 - SKU
# Returns: tab-separated: entity_id, sku, type_id, attribute_set_id
get_product_by_sku() {
    local sku="$1"
    magento_query "SELECT entity_id, sku, type_id, attribute_set_id FROM catalog_product_entity WHERE LOWER(TRIM(sku))=LOWER(TRIM('$sku')) LIMIT 1"
}

# Get product name by entity_id
# Args: $1 - entity_id
get_product_name() {
    local entity_id="$1"
    magento_query "SELECT value FROM catalog_product_entity_varchar WHERE entity_id=$entity_id AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=4) LIMIT 1"
}

# Get product price by entity_id
# Args: $1 - entity_id
get_product_price() {
    local entity_id="$1"
    magento_query "SELECT value FROM catalog_product_entity_decimal WHERE entity_id=$entity_id AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='price' AND entity_type_id=4) LIMIT 1"
}

# Get category by name (case-insensitive)
# Args: $1 - category name
get_category_by_name() {
    local name="$1"
    magento_query "SELECT e.entity_id, v.value as name, e.parent_id, e.level
        FROM catalog_category_entity e
        JOIN catalog_category_entity_varchar v ON e.entity_id = v.entity_id
        WHERE v.attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=3)
        AND LOWER(TRIM(v.value))=LOWER(TRIM('$name'))
        AND v.store_id = 0
        LIMIT 1"
}

# Get customer by email (case-insensitive)
# Args: $1 - email
get_customer_by_email() {
    local email="$1"
    magento_query "SELECT entity_id, email, firstname, lastname, group_id, created_at FROM customer_entity WHERE LOWER(TRIM(email))=LOWER(TRIM('$email')) LIMIT 1"
}

# Get customer by name (case-insensitive)
# Args: $1 - firstname, $2 - lastname
get_customer_by_name() {
    local firstname="$1"
    local lastname="$2"
    magento_query "SELECT entity_id, email, firstname, lastname, group_id, created_at FROM customer_entity WHERE LOWER(TRIM(firstname))=LOWER(TRIM('$firstname')) AND LOWER(TRIM(lastname))=LOWER(TRIM('$lastname')) LIMIT 1"
}

# Get newest product (by entity_id)
get_newest_product() {
    magento_query "SELECT entity_id, sku, type_id, attribute_set_id FROM catalog_product_entity ORDER BY entity_id DESC LIMIT 1"
}

# Get newest category
get_newest_category() {
    magento_query "SELECT e.entity_id, v.value as name, e.parent_id, e.level
        FROM catalog_category_entity e
        JOIN catalog_category_entity_varchar v ON e.entity_id = v.entity_id
        WHERE v.attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=3)
        AND v.store_id = 0
        ORDER BY e.entity_id DESC LIMIT 1"
}

# Get newest customer
get_newest_customer() {
    magento_query "SELECT entity_id, email, firstname, lastname, group_id, created_at FROM customer_entity ORDER BY entity_id DESC LIMIT 1"
}

# =============================================================================
# Window Management Utilities
# =============================================================================

# Wait for a window with specified title to appear
# Args: $1 - window title pattern (grep pattern)
#       $2 - timeout in seconds (default: 30)
wait_for_window() {
    local window_pattern="$1"
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for window matching '$window_pattern'..."

    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then
            echo "Window found after ${elapsed}s"
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: Window not found after ${timeout}s"
    return 1
}

# Focus a window
# Args: $1 - window ID
focus_window() {
    local window_id="$1"

    if DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null || DISPLAY=:1 wmctrl -a "$window_id" 2>/dev/null; then
        sleep 0.3
        echo "Window focused: $window_id"
        return 0
    fi

    echo "Failed to focus window: $window_id"
    return 1
}

# Get the window ID for Firefox
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'
}

# Take a screenshot
# Args: $1 - output file path (default: /tmp/screenshot.png)
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
    echo "Warning: Could not take screenshot"
    [ -f "$output_file" ] && echo "Screenshot saved: $output_file"
}

# =============================================================================
# JSON Export Utilities
# =============================================================================

# Safely write a JSON result file
# Args: $1 - temp file (already written), $2 - final destination path
safe_write_json() {
    local temp_file="$1"
    local dest_path="$2"

    # Remove old file
    rm -f "$dest_path" 2>/dev/null || sudo rm -f "$dest_path" 2>/dev/null || true

    # Copy temp to final
    cp "$temp_file" "$dest_path" 2>/dev/null || sudo cp "$temp_file" "$dest_path"

    # Set permissions
    chmod 666 "$dest_path" 2>/dev/null || sudo chmod 666 "$dest_path" 2>/dev/null || true

    # Cleanup temp
    rm -f "$temp_file"

    echo "Result saved to $dest_path"
}

# =============================================================================
# Export functions for use in sourced scripts
# =============================================================================
export -f magento_query
export -f magento_query_headers
export -f get_product_count
export -f get_category_count
export -f get_customer_count
export -f get_order_count
export -f get_product_by_sku
export -f get_product_name
export -f get_product_price
export -f get_category_by_name
export -f get_customer_by_email
export -f get_customer_by_name
export -f get_newest_product
export -f get_newest_category
export -f get_newest_customer
export -f wait_for_window
export -f focus_window
export -f get_firefox_window_id
export -f take_screenshot
export -f safe_write_json
