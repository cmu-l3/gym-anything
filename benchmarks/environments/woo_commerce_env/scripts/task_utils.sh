#!/bin/bash
# Shared utilities for WooCommerce task setup and export scripts

# =============================================================================
# Database Utilities
# =============================================================================

# Check database connectivity
# Returns: 0 if connected, 1 if not
check_db_connection() {
    local result
    result=$(docker exec woocommerce-mariadb mysql -u wordpress -pwordpresspass wordpress -N -B -e "SELECT 1" 2>/dev/null)
    if [ "$result" = "1" ]; then
        return 0
    else
        echo "ERROR: Database connection failed. MariaDB container may not be running."
        return 1
    fi
}

# Escape a string for safe SQL embedding (prevents SQL injection from special chars)
# Doubles single quotes: O'Brien -> O''Brien
# Args: $1 - string to escape
# Returns: escaped string
sql_escape() {
    local str="$1"
    echo "${str//\'/\'\'}"
}

# Execute SQL query against WordPress database (via Docker)
# Args: $1 - SQL query
# Returns: query result (tab-separated, no column headers)
wc_query() {
    local query="$1"
    docker exec woocommerce-mariadb mysql -u wordpress -pwordpresspass wordpress -N -B -e "$query" 2>/dev/null
}

# Execute SQL query with column headers
wc_query_headers() {
    local query="$1"
    docker exec woocommerce-mariadb mysql -u wordpress -pwordpresspass wordpress -e "$query" 2>/dev/null
}

# =============================================================================
# Product Utilities
# =============================================================================

# Get total product count (published products only)
get_product_count() {
    wc_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='product' AND post_status='publish'"
}

# Get product by SKU (case-insensitive)
# Args: $1 - SKU
# Returns: tab-separated: post_id, sku
get_product_by_sku() {
    local sku
    sku=$(sql_escape "$1")
    wc_query "SELECT p.ID, pm.meta_value as sku
        FROM wp_posts p
        JOIN wp_postmeta pm ON p.ID = pm.post_id
        WHERE p.post_type = 'product'
        AND pm.meta_key = '_sku'
        AND LOWER(TRIM(pm.meta_value)) = LOWER(TRIM('$sku'))
        LIMIT 1"
}

# Get product name by post ID
# Args: $1 - post_id
get_product_name() {
    local post_id="$1"
    wc_query "SELECT post_title FROM wp_posts WHERE ID=$post_id AND post_type='product' LIMIT 1"
}

# Get product price by post ID
# Args: $1 - post_id
get_product_price() {
    local post_id="$1"
    wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$post_id AND meta_key='_regular_price' LIMIT 1"
}

# Get product sale price by post ID
# Args: $1 - post_id
get_product_sale_price() {
    local post_id="$1"
    wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$post_id AND meta_key='_sale_price' LIMIT 1"
}

# Get product stock quantity by post ID
# Args: $1 - post_id
get_product_stock() {
    local post_id="$1"
    wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$post_id AND meta_key='_stock' LIMIT 1"
}

# Get newest product (by ID)
get_newest_product() {
    wc_query "SELECT p.ID, pm.meta_value as sku, p.post_title
        FROM wp_posts p
        LEFT JOIN wp_postmeta pm ON p.ID = pm.post_id AND pm.meta_key = '_sku'
        WHERE p.post_type = 'product' AND p.post_status = 'publish'
        ORDER BY p.ID DESC LIMIT 1"
}

# Search product by name (case-insensitive partial match)
# Args: $1 - product name
get_product_by_name() {
    local name
    name=$(sql_escape "$1")
    wc_query "SELECT p.ID, pm.meta_value as sku, p.post_title
        FROM wp_posts p
        LEFT JOIN wp_postmeta pm ON p.ID = pm.post_id AND pm.meta_key = '_sku'
        WHERE p.post_type = 'product' AND p.post_status = 'publish'
        AND LOWER(p.post_title) LIKE LOWER('%$name%')
        ORDER BY p.ID DESC LIMIT 1"
}

# =============================================================================
# Category Utilities
# =============================================================================

# Get total product category count
get_category_count() {
    wc_query "SELECT COUNT(*) FROM wp_terms t
        JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
        WHERE tt.taxonomy = 'product_cat'"
}

# Get category by name (case-insensitive)
# Args: $1 - category name
get_category_by_name() {
    local name
    name=$(sql_escape "$1")
    wc_query "SELECT t.term_id, t.name, t.slug, tt.parent, tt.count
        FROM wp_terms t
        JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
        WHERE tt.taxonomy = 'product_cat'
        AND LOWER(TRIM(t.name)) = LOWER(TRIM('$name'))
        LIMIT 1"
}

# Get newest category
get_newest_category() {
    wc_query "SELECT t.term_id, t.name, t.slug, tt.parent, tt.count
        FROM wp_terms t
        JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
        WHERE tt.taxonomy = 'product_cat'
        ORDER BY t.term_id DESC LIMIT 1"
}

# Get categories assigned to a product
# Args: $1 - product post_id
# Returns: comma-separated list of category names
get_product_categories() {
    local post_id="$1"
    wc_query "SELECT GROUP_CONCAT(t.name SEPARATOR ',')
        FROM wp_terms t
        JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
        JOIN wp_term_relationships tr ON tt.term_taxonomy_id = tr.term_taxonomy_id
        WHERE tr.object_id = $post_id
        AND tt.taxonomy = 'product_cat'"
}

# Get product type (simple, variable, grouped, external)
# Args: $1 - product post_id
get_product_type() {
    local post_id="$1"
    wc_query "SELECT t.slug
        FROM wp_terms t
        JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
        JOIN wp_term_relationships tr ON tt.term_taxonomy_id = tr.term_taxonomy_id
        WHERE tr.object_id = $post_id
        AND tt.taxonomy = 'product_type'
        LIMIT 1"
}

# Get product post status (publish, draft, pending, etc.)
# Args: $1 - product post_id
get_product_status() {
    local post_id="$1"
    wc_query "SELECT post_status FROM wp_posts WHERE ID = $post_id AND post_type = 'product' LIMIT 1"
}

# =============================================================================
# Customer Utilities
# =============================================================================

# Get total customer count
get_customer_count() {
    wc_query "SELECT COUNT(*) FROM wp_users u
        JOIN wp_usermeta um ON u.ID = um.user_id
        WHERE um.meta_key = 'wp_capabilities'
        AND um.meta_value LIKE '%customer%'"
}

# Get customer by email (case-insensitive)
# Args: $1 - email
get_customer_by_email() {
    local email
    email=$(sql_escape "$1")
    wc_query "SELECT u.ID, u.user_email, u.user_login, u.display_name, u.user_registered
        FROM wp_users u
        WHERE LOWER(TRIM(u.user_email)) = LOWER(TRIM('$email'))
        LIMIT 1"
}

# Get customer by name
# Args: $1 - first name, $2 - last name
get_customer_by_name() {
    local firstname
    local lastname
    firstname=$(sql_escape "$1")
    lastname=$(sql_escape "$2")
    wc_query "SELECT u.ID, u.user_email, u.user_login, u.display_name, u.user_registered
        FROM wp_users u
        JOIN wp_usermeta fn ON u.ID = fn.user_id AND fn.meta_key = 'first_name'
        JOIN wp_usermeta ln ON u.ID = ln.user_id AND ln.meta_key = 'last_name'
        WHERE LOWER(TRIM(fn.meta_value)) = LOWER(TRIM('$firstname'))
        AND LOWER(TRIM(ln.meta_value)) = LOWER(TRIM('$lastname'))
        LIMIT 1"
}

# Get newest customer
get_newest_customer() {
    wc_query "SELECT u.ID, u.user_email, u.user_login, u.display_name, u.user_registered
        FROM wp_users u
        JOIN wp_usermeta um ON u.ID = um.user_id
        WHERE um.meta_key = 'wp_capabilities'
        AND um.meta_value LIKE '%customer%'
        ORDER BY u.ID DESC LIMIT 1"
}

# Get customer first name by user ID
# Args: $1 - user_id
get_customer_firstname() {
    local user_id="$1"
    wc_query "SELECT meta_value FROM wp_usermeta WHERE user_id=$user_id AND meta_key='first_name' LIMIT 1"
}

# Get customer last name by user ID
# Args: $1 - user_id
get_customer_lastname() {
    local user_id="$1"
    wc_query "SELECT meta_value FROM wp_usermeta WHERE user_id=$user_id AND meta_key='last_name' LIMIT 1"
}

# Get customer role by user ID
# Args: $1 - user_id
# Returns: serialized wp_capabilities value (e.g. a:1:{s:8:"customer";b:1;})
get_customer_role() {
    local user_id="$1"
    wc_query "SELECT meta_value FROM wp_usermeta WHERE user_id=$user_id AND meta_key='wp_capabilities' LIMIT 1"
}

# =============================================================================
# Coupon Utilities
# =============================================================================

# Get total coupon count
get_coupon_count() {
    wc_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='shop_coupon' AND post_status='publish'"
}

# Get coupon by code (case-insensitive)
# Args: $1 - coupon code
get_coupon_by_code() {
    local code
    code=$(sql_escape "$1")
    wc_query "SELECT ID, post_title, post_status
        FROM wp_posts
        WHERE post_type = 'shop_coupon'
        AND LOWER(TRIM(post_title)) = LOWER(TRIM('$code'))
        LIMIT 1"
}

# Get coupon discount type
# Args: $1 - coupon post_id
get_coupon_discount_type() {
    local post_id="$1"
    wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$post_id AND meta_key='discount_type' LIMIT 1"
}

# Get coupon amount
# Args: $1 - coupon post_id
get_coupon_amount() {
    local post_id="$1"
    wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$post_id AND meta_key='coupon_amount' LIMIT 1"
}

# Get newest coupon
get_newest_coupon() {
    wc_query "SELECT ID, post_title, post_status
        FROM wp_posts
        WHERE post_type = 'shop_coupon' AND post_status = 'publish'
        ORDER BY ID DESC LIMIT 1"
}

# =============================================================================
# Order Utilities
# =============================================================================

# Get total order count (excludes auto-drafts which are WooCommerce temp states)
get_order_count() {
    wc_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='shop_order' AND post_status != 'auto-draft'"
}

# =============================================================================
# Window Management Utilities
# =============================================================================

# Navigate Firefox to a URL reliably, handling both running and not-running cases.
# When Firefox is already running, uses xdotool to type URL into the address bar
# instead of launching a new Firefox process (which just opens a blank tab).
# Also dismisses any "Firefox is already running" dialogs.
# Args: $1 - URL to navigate to
navigate_firefox_to() {
    local url="${1:-http://localhost/wp-admin/?autologin=admin}"

    # Dismiss any "Firefox is already running" dialogs
    local dialog_wid
    dialog_wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "close firefox\|already running" | awk '{print $1}')
    if [ -n "$dialog_wid" ]; then
        echo "Dismissing Firefox dialog..."
        echo "$dialog_wid" | while read wid; do
            DISPLAY=:1 wmctrl -ic "$wid" 2>/dev/null || true
        done
        sleep 1
    fi

    if ! pgrep -f firefox > /dev/null; then
        # Firefox not running - launch fresh
        echo "Starting Firefox with URL: $url"
        su - ga -c "DISPLAY=:1 firefox '$url' > /tmp/firefox_task.log 2>&1 &"
        sleep 8
    else
        # Firefox is already running - navigate via xdotool to avoid blank tab
        echo "Firefox already running, navigating via address bar..."

        # Focus the Firefox window
        local wid
        wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | head -1 | awk '{print $1}')
        if [ -n "$wid" ]; then
            DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
            sleep 0.5
        fi

        # Ctrl+L focuses address bar, type URL, press Enter
        DISPLAY=:1 xdotool key ctrl+l
        sleep 0.3
        DISPLAY=:1 xdotool key ctrl+a
        sleep 0.1
        DISPLAY=:1 xdotool type --clearmodifiers "$url"
        sleep 0.2
        DISPLAY=:1 xdotool key Return
        sleep 5
    fi
}

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

# Wait for WordPress page to be fully loaded in Firefox
# This is MORE ROBUST than just checking for Firefox window - it verifies page content loaded
# by checking window title contains WordPress-specific text (Dashboard, WooCommerce, etc.)
# Args: $1 - timeout in seconds (default: 60)
# Returns: 0 if page loaded, 1 if timeout
wait_for_wordpress_page() {
    local timeout=${1:-60}
    local elapsed=0

    echo "Waiting for WordPress page to fully load (checking window title for Dashboard)..."

    while [ $elapsed -lt $timeout ]; do
        local window_title
        window_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)

        # Check for actual WordPress page titles (not just "Mozilla Firefox" or "New Tab")
        # Dashboard, WooCommerce, WordPress, etc. appear in title when page loads
        if echo "$window_title" | grep -qi "dashboard"; then
            echo "WordPress Dashboard page loaded after ${elapsed}s"
            echo "Window title: $window_title"
            return 0
        elif echo "$window_title" | grep -qi "wordpress.*—\|woocommerce.*—\|products.*—\|coupons.*—\|orders.*—\|users.*—"; then
            echo "WordPress admin page loaded after ${elapsed}s"
            echo "Window title: $window_title"
            return 0
        fi

        sleep 1
        elapsed=$((elapsed + 1))

        # Periodic status update
        if [ $((elapsed % 10)) -eq 0 ]; then
            echo "  Still waiting... ${elapsed}s (current title: $window_title)"
        fi
    done

    echo "WARNING: WordPress page did not load after ${timeout}s"
    echo "Current window title: $(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i firefox)"
    return 1
}

# Ensure Firefox is showing WordPress admin (not blank tab)
# If page is blank, attempts to navigate to WP admin
# Returns: 0 if WordPress is shown, 1 if failed
ensure_wordpress_shown() {
    local timeout=${1:-30}

    # First check if WordPress page is already loaded
    if wait_for_wordpress_page 5; then
        return 0
    fi

    echo "WordPress page not detected, checking Firefox state..."
    local window_title
    window_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
    echo "Current window title: $window_title"

    # If just showing "Mozilla Firefox" or "New Tab", page hasn't loaded
    if echo "$window_title" | grep -qi "new tab\|mozilla firefox$"; then
        echo "Firefox showing blank/new tab, refreshing page..."

        # Focus Firefox and try to navigate
        local wid
        wid=$(get_firefox_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid"
            sleep 0.5
        fi

        # Press F5 to refresh or Ctrl+L to open address bar
        DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 xdotool key ctrl+a 2>/dev/null || true
        sleep 0.1
        DISPLAY=:1 xdotool type --clearmodifiers "http://localhost/wp-admin/?autologin=admin" 2>/dev/null || true
        sleep 0.2
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 5

        # Wait for page to load
        if wait_for_wordpress_page "$timeout"; then
            return 0
        fi
    fi

    # Last resort: restart Firefox
    echo "Attempting to restart Firefox with correct URL..."
    pkill -f firefox 2>/dev/null || true
    sleep 2
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/?autologin=admin' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8

    wait_for_wordpress_page "$timeout"
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

# Escape a string for safe JSON embedding
# Handles double quotes, backslashes, newlines, tabs, and other control chars
# Args: $1 - string to escape
# Returns: escaped string (without surrounding quotes)
json_escape() {
    local str="$1"
    # Use python3 if available for reliable JSON escaping
    if command -v python3 &>/dev/null; then
        python3 -c "import json,sys; print(json.dumps(sys.argv[1])[1:-1])" "$str" 2>/dev/null
    else
        # Fallback: escape quotes and backslashes
        echo "$str" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g'
    fi
}

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
export -f check_db_connection
export -f sql_escape
export -f wc_query
export -f wc_query_headers
export -f get_product_count
export -f get_product_by_sku
export -f get_product_name
export -f get_product_price
export -f get_product_sale_price
export -f get_product_stock
export -f get_newest_product
export -f get_product_by_name
export -f get_category_count
export -f get_category_by_name
export -f get_newest_category
export -f get_product_categories
export -f get_product_type
export -f get_product_status
export -f get_customer_count
export -f get_customer_by_email
export -f get_customer_by_name
export -f get_newest_customer
export -f get_customer_firstname
export -f get_customer_lastname
export -f get_customer_role
export -f get_coupon_count
export -f get_coupon_by_code
export -f get_coupon_discount_type
export -f get_coupon_amount
export -f get_newest_coupon
export -f get_order_count
export -f navigate_firefox_to
export -f wait_for_window
export -f focus_window
export -f get_firefox_window_id
export -f take_screenshot
export -f wait_for_wordpress_page
export -f ensure_wordpress_shown
export -f json_escape
export -f safe_write_json
