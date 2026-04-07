#!/bin/bash
# Shared utilities for all iDempiere tasks

# ---------------------------------------------------------------
# Screenshot helper
# ---------------------------------------------------------------
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# ---------------------------------------------------------------
# PostgreSQL database query helper
# Query iDempiere's PostgreSQL database
# Usage: idempiere_query "SELECT name FROM c_bpartner LIMIT 5"
# ---------------------------------------------------------------
idempiere_query() {
    local query="$1"
    docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -c "$query" 2>/dev/null
}

# ---------------------------------------------------------------
# Get GardenWorld AD_Client_ID (typically 11 in standard seed data)
# ---------------------------------------------------------------
get_gardenworld_client_id() {
    idempiere_query "SELECT ad_client_id FROM ad_client WHERE name='GardenWorld' LIMIT 1"
}

# ---------------------------------------------------------------
# Check if a business partner with given name exists in GardenWorld
# ---------------------------------------------------------------
bp_exists() {
    local name="$1"
    local client_id
    client_id=$(get_gardenworld_client_id)
    local count
    count=$(idempiere_query "SELECT COUNT(*) FROM c_bpartner WHERE name='$name' AND ad_client_id=$client_id AND isactive='Y'" 2>/dev/null || echo "0")
    [ "$count" -gt 0 ] 2>/dev/null
}

# ---------------------------------------------------------------
# Check if a business partner with given search key (value) exists
# ---------------------------------------------------------------
bp_searchkey_exists() {
    local searchkey="$1"
    local client_id
    client_id=$(get_gardenworld_client_id)
    local count
    count=$(idempiere_query "SELECT COUNT(*) FROM c_bpartner WHERE value='$searchkey' AND ad_client_id=$client_id" 2>/dev/null || echo "0")
    [ "$count" -gt 0 ] 2>/dev/null
}

# ---------------------------------------------------------------
# Check if a product with given search key exists
# ---------------------------------------------------------------
product_searchkey_exists() {
    local searchkey="$1"
    local client_id
    client_id=$(get_gardenworld_client_id)
    local count
    count=$(idempiere_query "SELECT COUNT(*) FROM m_product WHERE value='$searchkey' AND ad_client_id=$client_id" 2>/dev/null || echo "0")
    [ "$count" -gt 0 ] 2>/dev/null
}

# ---------------------------------------------------------------
# Count sales orders for GardenWorld
# ---------------------------------------------------------------
get_sales_order_count() {
    local client_id
    client_id=$(get_gardenworld_client_id)
    idempiere_query "SELECT COUNT(*) FROM c_order WHERE issotrx='Y' AND ad_client_id=$client_id" 2>/dev/null || echo "0"
}

# ---------------------------------------------------------------
# Count purchase orders for GardenWorld
# ---------------------------------------------------------------
get_purchase_order_count() {
    local client_id
    client_id=$(get_gardenworld_client_id)
    idempiere_query "SELECT COUNT(*) FROM c_order WHERE issotrx='N' AND ad_client_id=$client_id" 2>/dev/null || echo "0"
}

# ---------------------------------------------------------------
# Count products for GardenWorld
# ---------------------------------------------------------------
get_product_count() {
    local client_id
    client_id=$(get_gardenworld_client_id)
    idempiere_query "SELECT COUNT(*) FROM m_product WHERE ad_client_id=$client_id AND isactive='Y'" 2>/dev/null || echo "0"
}

# ---------------------------------------------------------------
# Count GL journal entries for GardenWorld
# ---------------------------------------------------------------
get_journal_count() {
    local client_id
    client_id=$(get_gardenworld_client_id)
    idempiere_query "SELECT COUNT(*) FROM gl_journal WHERE ad_client_id=$client_id" 2>/dev/null || echo "0"
}

# ---------------------------------------------------------------
# Ensure iDempiere is accessible and Firefox is showing it
# Navigates Firefox to the specified iDempiere URL.
# Handles the ZK framework "Leave this page?" navigation guard.
# Usage: ensure_idempiere_open [optional_path]
# ---------------------------------------------------------------
ensure_idempiere_open() {
    local path="${1:-}"
    local url="https://localhost:8443/webui/${path}"

    # Navigate Firefox to the URL using address bar
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.2
    DISPLAY=:1 xdotool type --delay 20 "$url"
    DISPLAY=:1 xdotool key Return
    sleep 3

    # Handle ZK "Leave page?" browser dialog if it appears.
    # iDempiere's ZK framework intercepts navigation and shows a confirm dialog.
    # Coordinates confirmed at 1920x1080 (VG 758,437 -> actual 1137,656):
    #   "Leave page" button: actual (1137, 656)
    DISPLAY=:1 xdotool mousemove 1137 656
    sleep 0.3
    DISPLAY=:1 xdotool click 1
    sleep 8
}

# ---------------------------------------------------------------
# Navigate iDempiere to the main menu/dashboard
# ---------------------------------------------------------------
navigate_to_dashboard() {
    ensure_idempiere_open ""
    sleep 5
}

# ---------------------------------------------------------------
# List current active windows for debugging
# ---------------------------------------------------------------
list_windows() {
    DISPLAY=:1 wmctrl -l 2>/dev/null || echo "(wmctrl not available)"
}
