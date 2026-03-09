#!/bin/bash
# Setup script for Import Tax Rates CSV task

echo "=== Setting up Import Tax Rates CSV Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Enable tax calculation (prerequisite for seeing the Tax tab)
echo "Enabling tax calculation..."
wp option update woocommerce_calc_taxes "yes" --allow-root 2>/dev/null

# 2. Clear existing tax rates to ensure clean state
# This prevents "already exists" errors or count confusion
echo "Clearing existing tax rates..."
wc_query "TRUNCATE TABLE wp_woocommerce_tax_rates"
wc_query "TRUNCATE TABLE wp_woocommerce_tax_rate_locations"

# Record initial count (should be 0)
INITIAL_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_woocommerce_tax_rates" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_tax_count
echo "Initial tax rate count: $INITIAL_COUNT"

# 3. Generate the CSV file
CSV_PATH="/home/ga/Documents/wa_tax_rates.csv"
mkdir -p /home/ga/Documents
echo "Generating CSV file at $CSV_PATH..."

# WooCommerce Tax CSV Format:
# Country Code,State Code,Postcode,City,Rate,Tax Name,Priority,Compound,Shipping
cat > "$CSV_PATH" << EOF
Country Code,State Code,Postcode,City,Rate,Tax Name,Priority,Compound,Shipping
US,WA,98101,Seattle,10.2500,WA Sales Tax,1,0,1
US,WA,98004,Bellevue,10.1000,WA Sales Tax,1,0,1
US,WA,98402,Tacoma,10.3000,WA Sales Tax,1,0,1
US,WA,99201,Spokane,9.0000,WA Sales Tax,1,0,1
US,WA,98501,Olympia,9.4000,WA Sales Tax,1,0,1
US,WA,98201,Everett,9.9000,WA Sales Tax,1,0,1
US,WA,98901,Yakima,8.3000,WA Sales Tax,1,0,1
US,WA,98366,Port Orchard,9.2000,WA Sales Tax,1,0,1
US,WA,98660,Vancouver,8.5000,WA Sales Tax,1,0,1
US,WA,99336,Kennewick,8.6000,WA Sales Tax,1,0,1
US,WA,98052,Redmond,10.1000,WA Sales Tax,1,0,1
US,WA,98033,Kirkland,10.2000,WA Sales Tax,1,0,1
US,WA,98055,Renton,10.1000,WA Sales Tax,1,0,1
US,WA,98031,Kent,10.1000,WA Sales Tax,1,0,1
US,WA,98003,Federal Way,10.1000,WA Sales Tax,1,0,1
EOF

# Ensure user owns the file
chown ga:ga "$CSV_PATH"
chmod 644 "$CSV_PATH"

# 4. Ensure WordPress admin page is displayed
echo "Ensuring WordPress admin page is displayed..."
# Using the specific URL for tax settings to be helpful, but agent still needs to navigate to "Standard rates"
if ! ensure_wordpress_url "http://localhost/wp-admin/admin.php?page=wc-settings&tab=tax" 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# 5. Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "CSV created with 15 rows."