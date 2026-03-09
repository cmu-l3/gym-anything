#!/bin/bash
# WooCommerce Setup Script (post_start hook)
# Starts MariaDB via Docker, runs WordPress installer via WP-CLI,
# installs and configures WooCommerce, imports sample data, launches Firefox
#
# Default admin credentials: admin / Admin1234!

echo "=== Setting up WooCommerce ==="

# Configuration
WP_DIR="/var/www/html/wordpress"
WP_URL="http://localhost/"
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
ADMIN_EMAIL="admin@example.com"
DB_HOST="127.0.0.1"
DB_PORT="3306"
DB_NAME="wordpress"
DB_USER="wordpress"
DB_PASS="wordpresspass"

# Function to wait for MariaDB to be ready
wait_for_mariadb() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for MariaDB to be ready..."

    while [ $elapsed -lt $timeout ]; do
        if docker exec woocommerce-mariadb mysqladmin ping -h localhost -uroot -prootpass 2>/dev/null | grep -q "alive"; then
            echo "MariaDB is ready after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo "  Waiting for MariaDB... ${elapsed}s"
    done

    echo "WARNING: MariaDB readiness check timed out after ${timeout}s"
    return 1
}

# Function to wait for WordPress web to be ready
wait_for_wordpress() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for WordPress web interface to be ready..."

    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$WP_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            echo "WordPress web is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done

    echo "WARNING: WordPress readiness check timed out after ${timeout}s"
    return 1
}

# ============================================================
# 1. Start MariaDB via Docker Compose
# ============================================================
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/woocommerce
cp /workspace/config/docker-compose.yml /home/ga/woocommerce/
chown -R ga:ga /home/ga/woocommerce

echo "Starting MariaDB container..."
cd /home/ga/woocommerce
docker-compose pull
docker-compose up -d

# Wait for MariaDB
wait_for_mariadb 120

echo "Docker container status:"
docker-compose ps

# ============================================================
# 2. Configure WordPress via WP-CLI
# ============================================================
echo ""
echo "Configuring WordPress..."

cd "$WP_DIR"

# Create wp-config.php
wp config create \
    --dbname="$DB_NAME" \
    --dbuser="$DB_USER" \
    --dbpass="$DB_PASS" \
    --dbhost="$DB_HOST:$DB_PORT" \
    --allow-root 2>&1

# Install WordPress
echo "Running WordPress installation..."
wp core install \
    --url="$WP_URL" \
    --title="WooCommerce Store" \
    --admin_user="$ADMIN_USER" \
    --admin_password="$ADMIN_PASS" \
    --admin_email="$ADMIN_EMAIL" \
    --skip-email \
    --allow-root 2>&1

INSTALL_EXIT=$?
if [ $INSTALL_EXIT -ne 0 ]; then
    echo "WARNING: WordPress installer exited with code $INSTALL_EXIT"
    # Check if it's already installed
    if wp core is-installed --allow-root 2>/dev/null; then
        echo "WordPress is already installed"
    else
        echo "ERROR: WordPress installation failed."
        exit 1
    fi
fi

# Set permalink structure (required for WooCommerce REST API)
echo "Setting permalink structure..."
wp rewrite structure '/%postname%/' --allow-root 2>&1
wp rewrite flush --allow-root 2>&1

# CRITICAL: Create .htaccess manually (WP can't write it when running as root)
echo "Creating .htaccess for permalink support..."
cat > "$WP_DIR/.htaccess" << 'HTACCESSEOF'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTACCESSEOF
chown www-data:www-data "$WP_DIR/.htaccess"
chmod 644 "$WP_DIR/.htaccess"

# Restart Apache to pick up .htaccess
systemctl restart apache2
sleep 2

# ============================================================
# 3. Install and Activate WooCommerce
# ============================================================
echo ""
echo "Installing WooCommerce plugin..."
wp plugin install woocommerce --activate --allow-root 2>&1

# Install Storefront theme (official WooCommerce theme)
echo "Installing Storefront theme..."
wp theme install storefront --activate --allow-root 2>&1

# Install WordPress Importer plugin (for sample data XML import)
echo "Installing WordPress Importer plugin..."
wp plugin install wordpress-importer --activate --allow-root 2>&1

# ============================================================
# 4. Configure WooCommerce Settings
# ============================================================
echo ""
echo "Configuring WooCommerce settings..."

# Set store address and currency
wp option update woocommerce_store_address "123 Main Street" --allow-root 2>&1
wp option update woocommerce_store_address_2 "Suite 100" --allow-root 2>&1
wp option update woocommerce_store_city "San Francisco" --allow-root 2>&1
wp option update woocommerce_default_country "US:CA" --allow-root 2>&1
wp option update woocommerce_store_postcode "94105" --allow-root 2>&1
wp option update woocommerce_currency "USD" --allow-root 2>&1
wp option update woocommerce_currency_pos "left" --allow-root 2>&1
wp option update woocommerce_price_thousand_sep "," --allow-root 2>&1
wp option update woocommerce_price_decimal_sep "." --allow-root 2>&1
wp option update woocommerce_price_num_decimals "2" --allow-root 2>&1

# Enable tax and shipping
wp option update woocommerce_calc_taxes "yes" --allow-root 2>&1
wp option update woocommerce_enable_coupons "yes" --allow-root 2>&1
wp option update woocommerce_enable_guest_checkout "yes" --allow-root 2>&1

# Set product display settings
wp option update woocommerce_catalog_columns "4" --allow-root 2>&1
wp option update woocommerce_catalog_rows "4" --allow-root 2>&1

# Mark setup wizard as completed
wp option update woocommerce_onboarding_profile '{"completed":true}' --format=json --allow-root 2>&1
wp option update woocommerce_task_list_hidden "yes" --allow-root 2>&1
wp option update woocommerce_admin_notices '[]' --format=json --allow-root 2>&1

# Create WooCommerce pages
wp wc tool run install_pages --user=admin --allow-root 2>&1 || true

# ============================================================
# 5. Import WooCommerce Sample Product Data
# ============================================================
echo ""
echo "Importing WooCommerce sample product data..."

# Try XML import first (official WooCommerce sample data)
WC_SAMPLE_XML="$WP_DIR/wp-content/plugins/woocommerce/sample-data/sample_products.xml"
if [ -f "$WC_SAMPLE_XML" ]; then
    echo "Found WooCommerce sample data XML: $WC_SAMPLE_XML"
    wp import "$WC_SAMPLE_XML" --authors=create --allow-root 2>&1 || {
        echo "XML import failed, will seed via WP-CLI..."
    }
else
    echo "WooCommerce sample XML not found."
fi

# ============================================================
# 5b. Seed data via WP-CLI (reliable, no REST API needed)
# ============================================================
echo ""
echo "Seeding additional product data via WP-CLI..."

cd "$WP_DIR"

# Create product categories via WP-CLI
echo "Creating product categories..."
wp wc product_cat create --name="Electronics" --description="Electronic devices and accessories" --user=admin --allow-root 2>&1 || true
wp wc product_cat create --name="Clothing" --description="Apparel and fashion items" --user=admin --allow-root 2>&1 || true
wp wc product_cat create --name="Home & Garden" --description="Home decor and garden supplies" --user=admin --allow-root 2>&1 || true
wp wc product_cat create --name="Sports & Outdoors" --description="Sports equipment and outdoor gear" --user=admin --allow-root 2>&1 || true
wp wc product_cat create --name="Accessories" --description="Bags, wallets, and accessories" --user=admin --allow-root 2>&1 || true

# Create products via WP-CLI
echo "Creating products via WP-CLI..."
wp wc product create --name="Wireless Bluetooth Headphones" --sku="WBH-001" --regular_price="79.99" --type="simple" --status="publish" --description="Premium wireless Bluetooth headphones with active noise cancellation, 30-hour battery life, and comfortable over-ear design." --short_description="Premium wireless headphones with ANC" --manage_stock=true --stock_quantity=150 --user=admin --allow-root 2>&1 || true
wp wc product create --name="USB-C Laptop Charger 65W" --sku="USBC-065" --regular_price="34.99" --type="simple" --status="publish" --description="Universal 65W USB-C power adapter compatible with most modern laptops. GaN technology for compact size." --short_description="65W USB-C GaN charger" --manage_stock=true --stock_quantity=300 --user=admin --allow-root 2>&1 || true
wp wc product create --name="Organic Cotton T-Shirt" --sku="OCT-BLK-M" --regular_price="24.99" --type="simple" --status="publish" --description="Soft organic cotton t-shirt, fair-trade certified." --short_description="Organic fair-trade cotton tee" --manage_stock=true --stock_quantity=500 --user=admin --allow-root 2>&1 || true
wp wc product create --name="Slim Fit Denim Jeans" --sku="SFDJ-BLU-32" --regular_price="59.99" --type="simple" --status="publish" --description="Classic slim fit denim jeans made from premium stretch denim." --short_description="Slim fit stretch denim" --manage_stock=true --stock_quantity=200 --user=admin --allow-root 2>&1 || true
wp wc product create --name="Merino Wool Sweater" --sku="MWS-GRY-L" --regular_price="89.99" --type="simple" --status="publish" --description="Luxurious merino wool sweater. Naturally temperature regulating." --short_description="Premium merino wool sweater" --manage_stock=true --stock_quantity=120 --user=admin --allow-root 2>&1 || true
wp wc product create --name="Ceramic Plant Pot Set" --sku="CPP-SET3" --regular_price="42.99" --type="simple" --status="publish" --description="Set of 3 minimalist ceramic plant pots with drainage holes." --short_description="3-piece ceramic pot set" --manage_stock=true --stock_quantity=250 --user=admin --allow-root 2>&1 || true
wp wc product create --name="LED Desk Lamp" --sku="LED-DL-01" --regular_price="49.99" --type="simple" --status="publish" --description="Adjustable LED desk lamp with 5 brightness levels and 3 color temperatures." --short_description="Adjustable LED lamp with USB" --manage_stock=true --stock_quantity=400 --user=admin --allow-root 2>&1 || true
wp wc product create --name="Bamboo Cutting Board Set" --sku="BCB-SET2" --regular_price="29.99" --type="simple" --status="publish" --description="Set of 2 organic bamboo cutting boards." --short_description="2-piece bamboo cutting boards" --manage_stock=true --stock_quantity=350 --user=admin --allow-root 2>&1 || true
wp wc product create --name="Yoga Mat Premium" --sku="YMP-001" --regular_price="39.99" --type="simple" --status="publish" --description="Extra thick 6mm non-slip yoga mat with alignment lines." --short_description="Eco-friendly non-slip yoga mat" --manage_stock=true --stock_quantity=275 --user=admin --allow-root 2>&1 || true
wp wc product create --name="Insulated Water Bottle 32oz" --sku="IWB-032" --regular_price="27.99" --type="simple" --status="publish" --description="Double-wall vacuum insulated stainless steel water bottle." --short_description="32oz insulated steel bottle" --manage_stock=true --stock_quantity=600 --user=admin --allow-root 2>&1 || true
wp wc product create --name="Resistance Band Set" --sku="RBS-005" --regular_price="19.99" --type="simple" --status="publish" --description="Set of 5 resistance bands with different tension levels." --short_description="5-piece resistance band kit" --manage_stock=true --stock_quantity=450 --user=admin --allow-root 2>&1 || true
wp wc product create --name="Portable Camping Hammock" --sku="PCH-DUO" --regular_price="54.99" --type="simple" --status="publish" --description="Double-size camping hammock with tree straps. Supports up to 500 lbs." --short_description="Double camping hammock" --manage_stock=true --stock_quantity=180 --user=admin --allow-root 2>&1 || true

# Create coupons via WP-CLI
echo "Creating coupons via WP-CLI..."
wp wc shop_coupon create --code="WELCOME10" --discount_type="percent" --amount="10" --description="10% off welcome discount" --individual_use=true --usage_limit=100 --user=admin --allow-root 2>&1 || true
wp wc shop_coupon create --code="FREESHIP" --discount_type="fixed_cart" --amount="0" --description="Free shipping coupon" --free_shipping=true --usage_limit=500 --user=admin --allow-root 2>&1 || true
wp wc shop_coupon create --code="SAVE20" --discount_type="fixed_cart" --amount="20" --description="\$20 off orders over \$100" --individual_use=true --minimum_amount="100.00" --usage_limit=200 --user=admin --allow-root 2>&1 || true

# Create customer accounts via WP-CLI
echo "Creating customer accounts..."
wp user create johndoe john.doe@example.com --role=customer --first_name="John" --last_name="Doe" --user_pass="Customer123!" --allow-root 2>&1 || true
wp user create janesmith jane.smith@example.com --role=customer --first_name="Jane" --last_name="Smith" --user_pass="Customer123!" --allow-root 2>&1 || true
wp user create mikewilson mike.wilson@example.com --role=customer --first_name="Mike" --last_name="Wilson" --user_pass="Customer123!" --allow-root 2>&1 || true

echo "Data seeding complete!"
echo "Product count: $(wp post list --post_type=product --post_status=publish --format=count --allow-root 2>/dev/null)"
echo "Coupon count: $(wp post list --post_type=shop_coupon --post_status=publish --format=count --allow-root 2>/dev/null)"
echo "Customer count: $(wp user list --role=customer --format=count --allow-root 2>/dev/null)"

# ============================================================
# 5c. Install auto-login MU-plugin for test environment
# ============================================================
echo "Installing auto-login MU-plugin..."
mkdir -p "$WP_DIR/wp-content/mu-plugins"
cat > "$WP_DIR/wp-content/mu-plugins/auto-login.php" << 'MULOGINEOF'
<?php
/**
 * Auto-login MU-plugin for test environments.
 * Logs in as admin when ?autologin=admin is in the URL.
 * This is only for automated testing in QEMU environments.
 */
add_action('init', function() {
    if (isset($_GET['autologin']) && $_GET['autologin'] === 'admin' && !is_user_logged_in()) {
        $user = get_user_by('login', 'admin');
        if ($user) {
            wp_set_current_user($user->ID);
            wp_set_auth_cookie($user->ID, true);
            $redirect = remove_query_arg('autologin');
            if (empty($redirect) || $redirect === home_url('/')) {
                $redirect = admin_url();
            }
            wp_safe_redirect($redirect);
            exit;
        }
    }
});
MULOGINEOF
chown www-data:www-data "$WP_DIR/wp-content/mu-plugins/auto-login.php"
chmod 644 "$WP_DIR/wp-content/mu-plugins/auto-login.php"

# ============================================================
# 6. Fix permissions
# ============================================================
echo "Fixing permissions..."
chown -R www-data:www-data "$WP_DIR"
chmod -R 755 "$WP_DIR"
chmod -R 777 "$WP_DIR/wp-content/uploads" 2>/dev/null || true

# ============================================================
# 7. Restart Apache
# ============================================================
echo ""
echo "Restarting Apache..."
systemctl restart apache2

# Wait for WordPress to be accessible
wait_for_wordpress 120

# ============================================================
# 8. Create utility script for database queries
# ============================================================
cat > /usr/local/bin/wc-db-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against WordPress database (via Docker MariaDB)
docker exec woocommerce-mariadb mysql -u wordpress -pwordpresspass wordpress -e "$1"
DBQUERYEOF
chmod +x /usr/local/bin/wc-db-query

# ============================================================
# 9. Set up Firefox profile for user 'ga'
# ============================================================
echo "Setting up Firefox profile..."
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

# Create Firefox profiles.ini
cat > "$FIREFOX_PROFILE_DIR/profiles.ini" << 'FFPROFILE'
[Install4F96D1932A9F858E]
Default=default-release
Locked=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE
chown ga:ga "$FIREFOX_PROFILE_DIR/profiles.ini"

# Create user.js to configure Firefox
cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'USERJS'
// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to WooCommerce admin
user_pref("browser.startup.homepage", "http://localhost/wp-admin/");
user_pref("browser.startup.page", 1);

// Disable update checks
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable sidebar and other popups
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
USERJS
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/user.js"

# Set ownership of Firefox profile
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/WooCommerce.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=WooCommerce Admin
Comment=WooCommerce Store Administration
Exec=firefox http://localhost/wp-admin/
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/WooCommerce.desktop
chmod +x /home/ga/Desktop/WooCommerce.desktop

# ============================================================
# 10. Launch Firefox
# ============================================================
echo "Launching Firefox with WooCommerce admin (auto-login)..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/?autologin=admin' > /tmp/firefox_woocommerce.log 2>&1 &"

# Wait for Firefox window to appear
sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    # Maximize Firefox window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi

    # CRITICAL: Wait for WordPress admin page to FULLY RENDER (not just window title)
    # The window title check is insufficient - Firefox shows "Mozilla Firefox" before page loads
    # We need to verify actual page content is rendered by checking window title contains "Dashboard"
    # AND the page has finished loading (title changes from "Mozilla Firefox" to page title)
    echo "Waiting for WordPress admin page to fully render..."
    PAGE_LOADED=false

    # First wait: Check if window title contains WordPress-specific text (not just "Mozilla Firefox")
    for i in {1..60}; do
        WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
        # Check for actual WordPress page title (Dashboard, WordPress, WooCommerce)
        # Exclude matches that are just "Mozilla Firefox" without page title
        if echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
            PAGE_LOADED=true
            echo "WordPress Dashboard detected in window title after ${i}s"
            echo "Window title: $WINDOW_TITLE"
            break
        elif echo "$WINDOW_TITLE" | grep -qi "wordpress.*—.*mozilla\|woocommerce.*—.*mozilla"; then
            PAGE_LOADED=true
            echo "WordPress page detected in window title after ${i}s"
            echo "Window title: $WINDOW_TITLE"
            break
        fi
        sleep 1
    done

    if [ "$PAGE_LOADED" = false ]; then
        echo "WARNING: WordPress admin page title not detected after 60s"
        echo "Current window title: $(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i firefox)"
        # Try refreshing the page
        echo "Attempting to refresh the page..."
        DISPLAY=:1 xdotool key F5 2>/dev/null || true
        sleep 10
        # Check again
        WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
        if echo "$WINDOW_TITLE" | grep -qi "dashboard\|wordpress\|woocommerce"; then
            PAGE_LOADED=true
            echo "Page loaded after refresh"
        fi
    fi

    # Additional wait for page rendering (CSS, JavaScript)
    echo "Waiting additional 10s for page rendering..."
    sleep 10

    # Final verification: Take a test screenshot and log the result
    echo "Taking verification screenshot..."
    DISPLAY=:1 import -window root /tmp/setup_verification.png 2>/dev/null || true

    # Log final window state
    echo "Final window list:"
    DISPLAY=:1 wmctrl -l 2>/dev/null || true
fi

echo ""
echo "=== WooCommerce Setup Complete ==="
echo ""
echo "WooCommerce store is running at: $WP_URL"
echo "Admin panel: ${WP_URL}wp-admin/"
echo ""
echo "Login Credentials:"
echo "  Admin: ${ADMIN_USER} / ${ADMIN_PASS}"
echo ""
echo "Pre-loaded Data:"
echo "  - 12 products across 4 categories (Electronics, Clothing, Home & Garden, Sports & Outdoors)"
echo "  - 3 coupons (WELCOME10, FREESHIP, SAVE20)"
echo "  - 3 customers (John Doe, Jane Smith, Mike Wilson)"
echo "  - WooCommerce sample products (if XML import succeeded)"
echo ""
echo "Database access (via Docker):"
echo "  wc-db-query \"SELECT COUNT(*) FROM wp_posts WHERE post_type='product'\""
echo ""
