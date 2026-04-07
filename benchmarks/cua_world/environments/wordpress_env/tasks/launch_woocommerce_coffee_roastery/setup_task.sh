#!/bin/bash
# Setup script for launch_woocommerce_coffee_roastery task (pre_task hook)
# Installs WooCommerce (NOT activated), creates data files for the agent.

echo "=== Setting up launch_woocommerce_coffee_roastery task ==="

source /workspace/scripts/task_utils.sh

cd /var/www/html/wordpress

# ============================================================
# 1. Clean up from any prior runs
# ============================================================
echo "Cleaning up prior run data..."

# Deactivate WooCommerce if active (so we can clean up)
wp plugin deactivate woocommerce --allow-root 2>/dev/null || true

# Delete any existing WooCommerce products
PRODUCT_IDS=$(wp post list --post_type=product --format=ids --allow-root 2>/dev/null)
if [ -n "$PRODUCT_IDS" ]; then
    wp post delete $PRODUCT_IDS --force --allow-root 2>/dev/null || true
fi

# Delete any existing product variations
VARIATION_IDS=$(wp post list --post_type=product_variation --format=ids --allow-root 2>/dev/null)
if [ -n "$VARIATION_IDS" ]; then
    wp post delete $VARIATION_IDS --force --allow-root 2>/dev/null || true
fi

# Delete any existing coupons
COUPON_IDS=$(wp post list --post_type=shop_coupon --format=ids --allow-root 2>/dev/null)
if [ -n "$COUPON_IDS" ]; then
    wp post delete $COUPON_IDS --force --allow-root 2>/dev/null || true
fi

# Clean WooCommerce product categories (but not 'Uncategorized')
wp_db_query "DELETE t, tt, tr FROM wp_terms t
    INNER JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
    LEFT JOIN wp_term_relationships tr ON tt.term_taxonomy_id = tr.term_taxonomy_id
    WHERE tt.taxonomy = 'product_cat'" 2>/dev/null || true

# Clean product attributes registrations
wp_db_query "DELETE FROM wp_woocommerce_attribute_taxonomies" 2>/dev/null || true

# Clean attribute terms (pa_*)
wp_db_query "DELETE t, tt FROM wp_terms t
    INNER JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
    WHERE tt.taxonomy LIKE 'pa\\_%'" 2>/dev/null || true

# Clean shipping zones
wp_db_query "DELETE FROM wp_woocommerce_shipping_zones" 2>/dev/null || true
wp_db_query "DELETE FROM wp_woocommerce_shipping_zone_methods" 2>/dev/null || true
wp_db_query "DELETE FROM wp_woocommerce_shipping_zone_locations" 2>/dev/null || true

# Clean tax rates
wp_db_query "DELETE FROM wp_woocommerce_tax_rates" 2>/dev/null || true
wp_db_query "DELETE FROM wp_woocommerce_tax_rate_locations" 2>/dev/null || true

# Reset WooCommerce-specific options
for opt in woocommerce_calc_taxes woocommerce_currency woocommerce_store_address \
           woocommerce_store_city woocommerce_store_postcode woocommerce_default_country; do
    wp option delete "$opt" --allow-root 2>/dev/null || true
done

# Fully delete and reinstall WooCommerce for a clean state
wp plugin delete woocommerce --allow-root 2>/dev/null || true

# Clean up data files from prior run
rm -rf /home/ga/Documents/Store_Launch 2>/dev/null || true

# Clean up result files from prior run
rm -f /tmp/launch_woocommerce_coffee_roastery_result.json 2>/dev/null || true
rm -f /tmp/task_baseline.json 2>/dev/null || true

# ============================================================
# 2. Install WooCommerce (NOT activate)
# ============================================================
echo "Installing WooCommerce plugin (not activating)..."
wp plugin install woocommerce --allow-root 2>&1
INSTALL_EXIT=$?

if [ $INSTALL_EXIT -ne 0 ]; then
    echo "WARNING: WP-CLI install failed (exit $INSTALL_EXIT), trying direct download..."
    cd /tmp
    curl -sL "https://downloads.wordpress.org/plugin/woocommerce.latest-stable.zip" -o woocommerce.zip 2>/dev/null || \
    wget -q "https://downloads.wordpress.org/plugin/woocommerce.latest-stable.zip" -O woocommerce.zip 2>/dev/null
    if [ -f /tmp/woocommerce.zip ]; then
        cd /var/www/html/wordpress/wp-content/plugins
        unzip -o /tmp/woocommerce.zip 2>/dev/null
        rm -f /tmp/woocommerce.zip
        chown -R www-data:www-data /var/www/html/wordpress/wp-content/plugins/woocommerce
        echo "WooCommerce installed via direct download"
    else
        echo "ERROR: Failed to download WooCommerce"
    fi
    cd /var/www/html/wordpress
fi

# Ensure correct ownership (wp plugin install runs as root)
chown -R www-data:www-data /var/www/html/wordpress/wp-content/plugins/woocommerce 2>/dev/null || true

# Verify WooCommerce is installed but not active
WC_STATUS=$(wp plugin status woocommerce --allow-root 2>/dev/null | grep -i "status" || echo "installed (inactive)")
echo "WooCommerce status: $WC_STATUS"

# ============================================================
# 3. Create data files
# ============================================================
echo "Creating data files..."
mkdir -p /home/ga/Documents/Store_Launch

cat > /home/ga/Documents/Store_Launch/product_catalog.csv << 'CSVEOF'
name,sku,parent_category,subcategory,type,regular_price,description,price_250g,price_500g,price_1kg
Ethiopian Yirgacheffe,SR-ETH-001,Single Origin,African,variable,,Bright and fruity with notes of blueberry and citrus from the Gedeo zone. Washed process.,14.99,26.99,48.99
Colombian Supremo,SR-COL-002,Single Origin,Americas,variable,,Rich and balanced with caramel sweetness and nutty undertones from Huila region.,13.99,24.99,44.99
Morning Symphony,SR-BLD-001,Blends,,variable,,A smooth and approachable blend of Brazilian and Colombian beans for daily brewing.,12.99,22.99,41.99
Hario V60 Dripper,SR-EQP-001,Equipment,,simple,32.00,Ceramic pour-over dripper. Size 02 serves 1-4 cups for clean extraction.,,,
Baratza Encore Grinder,SR-EQP-002,Equipment,,simple,169.99,Conical burr grinder with 40 grind settings. Ideal entry-level grinder for home brewing.,,,
Fellow Stagg Kettle,SR-EQP-003,Equipment,,simple,89.95,Precision pour-over kettle with built-in thermometer and 1.0 liter capacity.,,,
CSVEOF

cat > /home/ga/Documents/Store_Launch/store_brief.txt << 'BRIEFEOF'
Summit Roasters - Online Store Launch Brief

STORE ADDRESS:
415 Westlake Avenue
Seattle, WA 98109
United States

CURRENCY: USD ($)

TAX: Enable tax calculations.
Standard rate: 6.5% for state code WA (Washington), all zip codes.
Tax name: "WA Sales Tax"

SELLING: All countries
SHIPPING: United States only

SHIPPING ZONE: "Domestic US" covering United States
- Flat Rate: $5.99
- Free Shipping: minimum order amount $75.00

PRODUCT ATTRIBUTE:
- Name: Bag Size
- Values: 250g | 500g | 1kg
- Used for variations on all coffee products

COUPON:
- Code: GRANDOPENING
- Type: Percentage discount
- Amount: 20%
- Usage limit: 500 total uses
- Expiry: December 31, 2026
BRIEFEOF

chown -R ga:ga /home/ga/Documents/Store_Launch
chmod -R 644 /home/ga/Documents/Store_Launch/*
chmod 755 /home/ga/Documents/Store_Launch

echo "Data files created:"
echo "  ~/Documents/Store_Launch/product_catalog.csv"
echo "  ~/Documents/Store_Launch/store_brief.txt"

# ============================================================
# 4. Record baseline and timestamp
# ============================================================
echo "Recording baseline state..."

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

cat > /tmp/task_baseline.json << 'BASEEOF'
{
    "wc_status": "inactive",
    "product_count": 0,
    "category_count": 0,
    "attribute_count": 0,
    "coupon_count": 0,
    "shipping_zone_count": 0
}
BASEEOF
chmod 666 /tmp/task_baseline.json

# ============================================================
# 5. Ensure Firefox is running and focused
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/?autologin=admin' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "WooCommerce installed but NOT activated."
echo "Data files at ~/Documents/Store_Launch/"
echo "Agent must: activate WooCommerce, configure store, create categories,"
echo "create Bag Size attribute, add 6 products (3 variable, 3 simple),"
echo "configure shipping zone, tax rate, and coupon."
