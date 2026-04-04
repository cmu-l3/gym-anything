#!/bin/bash
# Shared utilities for Odoo Inventory task setup and export scripts

# Database configuration
DB_NAME="odoo_inventory"
DB_USER="odoo"
DB_PASS="odoo"
DB_HOST="localhost"

# Wait for a window with specified title to appear
# Args: $1 - window title pattern (grep pattern)
#       $2 - timeout in seconds (default: 30)
# Returns: 0 if found, 1 if timeout
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

# Wait for a file to be created or modified
# Args: $1 - file path
#       $2 - timeout in seconds (default: 10)
# Returns: 0 if file exists and was recently modified, 1 if timeout
wait_for_file() {
    local filepath="$1"
    local timeout=${2:-10}
    local start=$(date +%s)

    echo "Waiting for file: $filepath"

    while [ $(($(date +%s) - start)) -lt $timeout ]; do
        if [ -f "$filepath" ]; then
            if [ $(find "$filepath" -mmin -0.2 2>/dev/null | wc -l) -gt 0 ] || \
               [ $(($(date +%s) - start)) -lt 2 ]; then
                echo "File ready: $filepath"
                return 0
            fi
        fi
        sleep 0.5
    done

    echo "Timeout: File not updated: $filepath"
    return 1
}

# Wait for a process to start
# Args: $1 - process name pattern (pgrep pattern)
#       $2 - timeout in seconds (default: 20)
# Returns: 0 if process found, 1 if timeout
wait_for_process() {
    local process_pattern="$1"
    local timeout=${2:-20}
    local elapsed=0

    echo "Waiting for process matching '$process_pattern'..."

    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "$process_pattern" > /dev/null; then
            echo "Process found after ${elapsed}s"
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: Process not found after ${timeout}s"
    return 1
}

# Focus a window and verify it was focused
# Args: $1 - window ID or name pattern
# Returns: 0 if focused successfully, 1 otherwise
focus_window() {
    local window_id="$1"

    if DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null || DISPLAY=:1 wmctrl -a "$window_id" 2>/dev/null; then
        sleep 0.3
        if DISPLAY=:1 wmctrl -lpG 2>/dev/null | grep -q "$window_id"; then
            echo "Window focused: $window_id"
            return 0
        fi
    fi

    echo "Failed to focus window: $window_id"
    return 1
}

# Get the window ID for Firefox
# Returns: window ID or empty string
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'
}

# Safe xdotool command with display and user context
# Args: $1 - user (e.g., "ga")
#       $2 - display (e.g., ":1")
#       rest - xdotool arguments
safe_xdotool() {
    local user="$1"
    local display="$2"
    shift 2

    su - "$user" -c "DISPLAY=$display xdotool $*" 2>&1 | grep -v "^$"
    return ${PIPESTATUS[0]}
}

# Execute SQL query against Odoo PostgreSQL database (via Docker)
# Args: $1 - SQL query
# Returns: query result
odoo_query() {
    local query="$1"
    docker exec odoo-postgres psql -U $DB_USER -d $DB_NAME -t -A -c "$query" 2>/dev/null
}

# Execute SQL query and return rows (tab-separated)
odoo_query_rows() {
    local query="$1"
    docker exec odoo-postgres psql -U $DB_USER -d $DB_NAME -t -A -F $'\t' -c "$query" 2>/dev/null
}

# Extract English value from Odoo JSONB field
# Odoo 17 stores translatable fields as JSONB: {"en_US": "value", "es_ES": "valor"}
# Args: $1 - JSONB value
# Returns: English text or original value if not JSONB
extract_translation() {
    local value="$1"
    # Check if it looks like JSONB (starts with {)
    if [[ "$value" == \{* ]]; then
        # Extract en_US value using sed
        echo "$value" | sed -n 's/.*"en_US": *"\([^"]*\)".*/\1/p'
    else
        echo "$value"
    fi
}

# Get product count from database
get_product_count() {
    odoo_query "SELECT COUNT(*) FROM product_template"
}

# Get stock move count
get_stock_move_count() {
    odoo_query "SELECT COUNT(*) FROM stock_move"
}

# Get stock picking count (transfers)
get_stock_picking_count() {
    odoo_query "SELECT COUNT(*) FROM stock_picking"
}

# Get stock quant count (inventory levels)
get_stock_quant_count() {
    odoo_query "SELECT COUNT(*) FROM stock_quant"
}

# Check if product exists by name (case-insensitive)
# Args: $1 - product name
# Returns: 0 if found, 1 if not found
product_exists() {
    local name="$1"
    local count=$(odoo_query "SELECT COUNT(*) FROM product_template WHERE LOWER(name) = LOWER('$name')")
    [ "$count" -gt 0 ]
}

# Get product ID by name
# Args: $1 - product name
# Returns: product ID or empty string
get_product_id() {
    local name="$1"
    odoo_query "SELECT id FROM product_template WHERE LOWER(name) = LOWER('$name') LIMIT 1"
}

# Get stock location ID by name
# Args: $1 - location name
# Returns: location ID or empty string
get_location_id() {
    local name="$1"
    odoo_query "SELECT id FROM stock_location WHERE LOWER(name) = LOWER('$name') OR LOWER(complete_name) LIKE LOWER('%$name%') LIMIT 1"
}

# Get warehouse ID by name
# Args: $1 - warehouse name
# Returns: warehouse ID or empty string
get_warehouse_id() {
    local name="$1"
    odoo_query "SELECT id FROM stock_warehouse WHERE LOWER(name) = LOWER('$name') OR LOWER(code) = LOWER('$name') LIMIT 1"
}

# Get current stock quantity for a product in a location
# Args: $1 - product_id, $2 - location_id (optional)
get_stock_quantity() {
    local product_id="$1"
    local location_id="${2:-}"

    if [ -n "$location_id" ]; then
        odoo_query "SELECT COALESCE(SUM(quantity), 0) FROM stock_quant WHERE product_id = $product_id AND location_id = $location_id"
    else
        odoo_query "SELECT COALESCE(SUM(quantity), 0) FROM stock_quant WHERE product_id = $product_id"
    fi
}

# Take a screenshot
# Args: $1 - output file path (default: /tmp/screenshot.png)
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    # Use ImageMagick's import command (more reliable than scrot)
    DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
    echo "Warning: Could not take screenshot"
    [ -f "$output_file" ] && echo "Screenshot saved: $output_file"
}

# Safe JSON value escaping
# Args: $1 - value to escape
json_escape() {
    local value="$1"
    # Escape special chars, replace newlines, and trim whitespace
    echo "$value" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\t/\\t/g' | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Export these functions for use in other scripts
export -f wait_for_window
export -f wait_for_file
export -f wait_for_process
export -f focus_window
export -f get_firefox_window_id
export -f safe_xdotool
export -f odoo_query
export -f odoo_query_rows
export -f get_product_count
export -f get_stock_move_count
export -f get_stock_picking_count
export -f get_stock_quant_count
export -f product_exists
export -f get_product_id
export -f get_location_id
export -f get_warehouse_id
export -f get_stock_quantity
export -f take_screenshot
export -f json_escape
