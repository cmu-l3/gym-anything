#!/bin/bash
# Drupal Commerce Setup Script (post_start hook)
# Starts MariaDB via Docker, runs Drupal installer via Drush,
# enables and configures Commerce, imports sample data, launches Firefox
#
# Default admin credentials: admin / Admin1234!

echo "=== Setting up Drupal Commerce ==="

# Configuration
DRUPAL_DIR="/var/www/html/drupal"
DRUPAL_URL="http://localhost/"
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
ADMIN_EMAIL="admin@example.com"
DB_HOST="127.0.0.1"
DB_PORT="3306"
DB_NAME="drupal"
DB_USER="drupal"
DB_PASS="drupalpass"
DRUSH="$DRUPAL_DIR/vendor/bin/drush"
DOCKERHUB_TOKEN="dckr_pat_YISK01jQAaGVVmzkVoZnkOH3Q3g"
DOCKERHUB_USERNAME="hackear2041"
echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin

# ============================================================
# 0. Check if Drupal files are installed (pre_start may have timed out)
# ============================================================
if [ ! -f "$DRUPAL_DIR/vendor/bin/drush" ]; then
    echo "Drupal installation incomplete. Completing Composer installation..."
    export COMPOSER_ALLOW_SUPERUSER=1
    if [ ! -f "$DRUPAL_DIR/composer.json" ]; then
        echo "Drupal project missing, running composer create-project..."
        cd /var/www/html
        rm -rf drupal 2>/dev/null || true
        composer create-project drupal/recommended-project drupal --no-interaction 2>&1
        cd "$DRUPAL_DIR"
        composer config minimum-stability RC 2>&1
    fi
    cd "$DRUPAL_DIR"
    composer require drush/drush --no-interaction 2>&1 || true
    composer require drupal/commerce -W --no-interaction 2>&1 || true
    composer require drupal/admin_toolbar --no-interaction 2>&1 || true
    chown -R www-data:www-data "$DRUPAL_DIR"
    chmod -R 755 "$DRUPAL_DIR"
fi

# Ensure Apache config is in place
if [ ! -f /etc/apache2/sites-available/drupal.conf ]; then
    echo "Apache drupal.conf missing, recreating..."
    cat > /etc/apache2/sites-available/drupal.conf << 'APACHEEOF'
<VirtualHost *:80>
    ServerAdmin admin@localhost
    DocumentRoot /var/www/html/drupal/web

    <Directory /var/www/html/drupal/web>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/drupal_error.log
    CustomLog ${APACHE_LOG_DIR}/drupal_access.log combined
</VirtualHost>
APACHEEOF
    a2dissite 000-default.conf 2>/dev/null || true
    a2ensite drupal.conf 2>/dev/null || true
    a2enmod rewrite 2>/dev/null || true
    a2enmod headers 2>/dev/null || true
    systemctl restart apache2
fi

# Function to wait for MariaDB to be ready
wait_for_mariadb() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for MariaDB to be ready..."

    while [ $elapsed -lt $timeout ]; do
        if docker exec drupal-mariadb mysqladmin ping -h localhost -uroot -prootpass 2>/dev/null | grep -q "alive"; then
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

# Function to wait for Drupal web interface to be ready
wait_for_drupal() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for Drupal web interface to be ready..."

    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$DRUPAL_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            echo "Drupal web is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done

    echo "WARNING: Drupal readiness check timed out after ${timeout}s"
    return 1
}

# ============================================================
# 1. Start MariaDB via Docker Compose
# ============================================================
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/drupal_commerce
cp /workspace/config/docker-compose.yml /home/ga/drupal_commerce/
chown -R ga:ga /home/ga/drupal_commerce

echo "Starting MariaDB container..."
cd /home/ga/drupal_commerce
docker-compose pull
docker-compose up -d

# Wait for MariaDB
wait_for_mariadb 120

echo "Docker container status:"
docker-compose ps

# ============================================================
# 2. Install Drupal via Drush
# ============================================================
echo ""
echo "Installing Drupal..."

cd "$DRUPAL_DIR"

# Ensure settings.php is writable for installation
mkdir -p "$DRUPAL_DIR/web/sites/default/files"
chmod 777 "$DRUPAL_DIR/web/sites/default"
cp "$DRUPAL_DIR/web/sites/default/default.settings.php" "$DRUPAL_DIR/web/sites/default/settings.php" 2>/dev/null || true
chmod 666 "$DRUPAL_DIR/web/sites/default/settings.php"

# Install Drupal using Drush
echo "Running Drupal site installation..."
$DRUSH site:install standard \
    --db-url="mysql://$DB_USER:$DB_PASS@$DB_HOST:$DB_PORT/$DB_NAME" \
    --site-name="Drupal Commerce Store" \
    --account-name="$ADMIN_USER" \
    --account-pass="$ADMIN_PASS" \
    --account-mail="$ADMIN_EMAIL" \
    --locale=en \
    --yes 2>&1

INSTALL_EXIT=$?
if [ $INSTALL_EXIT -ne 0 ]; then
    echo "WARNING: Drupal installer exited with code $INSTALL_EXIT"
    if $DRUSH status --field=bootstrap 2>/dev/null | grep -q "Successful"; then
        echo "Drupal is already installed"
    else
        echo "ERROR: Drupal installation failed."
        exit 1
    fi
fi

# Lock down settings.php
chmod 444 "$DRUPAL_DIR/web/sites/default/settings.php"
chmod 555 "$DRUPAL_DIR/web/sites/default"

# ============================================================
# 3. Enable Commerce Modules
# ============================================================
echo ""
echo "Enabling Commerce modules..."

$DRUSH en -y commerce 2>&1
$DRUSH en -y commerce_product 2>&1
$DRUSH en -y commerce_order 2>&1
$DRUSH en -y commerce_cart 2>&1
$DRUSH en -y commerce_checkout 2>&1
$DRUSH en -y commerce_payment 2>&1
$DRUSH en -y commerce_promotion 2>&1
$DRUSH en -y commerce_tax 2>&1
$DRUSH en -y commerce_store 2>&1
$DRUSH en -y commerce_price 2>&1
$DRUSH en -y commerce_log 2>&1 || true

# Enable Admin Toolbar for better admin UX
$DRUSH en -y admin_toolbar admin_toolbar_tools 2>&1 || true

# Clear caches
$DRUSH cr 2>&1

# ============================================================
# 4. Grant Commerce Permissions to Admin
# ============================================================
echo ""
echo "Granting Commerce permissions to admin..."

$DRUSH role:perm:add administrator \
    "administer commerce_store,access commerce administration pages,administer commerce_order,administer commerce_product,administer commerce_product_type,administer commerce_promotion,administer commerce_payment,access commerce_order overview,view commerce_product,create default commerce_product,update any default commerce_product,delete any default commerce_product,manage default commerce_product_variation,view own commerce_order,manage default commerce_order_item" 2>&1

$DRUSH user:role:add administrator admin 2>&1

# ============================================================
# 5. Seed Data Using PHP Scripts
# ============================================================
echo ""
echo "Seeding product and promotion data..."

# The PHP seed scripts are mounted read-only. Copy them to a writable location.
cp /workspace/scripts/seed_products.php /tmp/seed_products.php 2>/dev/null || true
cp /workspace/scripts/seed_promotions.php /tmp/seed_promotions.php 2>/dev/null || true

# If seed scripts exist, run them
if [ -f /tmp/seed_products.php ]; then
    echo "Running product seed script..."
    $DRUSH php:script /tmp/seed_products.php 2>&1
else
    echo "Product seed script not found, creating inline..."
    $DRUSH php:eval '
use Drupal\commerce_store\Entity\Store;
$store = Store::create([
  "type" => "online", "uid" => 1, "name" => "Urban Electronics",
  "mail" => "store@urbanelectronics.com",
  "address" => ["country_code" => "US", "address_line1" => "456 Market Street",
    "locality" => "San Francisco", "administrative_area" => "CA", "postal_code" => "94105"],
  "default_currency" => "USD", "is_default" => TRUE,
]);
$store->save();
echo "Store created: " . $store->getName() . "\n";
' 2>&1
fi

if [ -f /tmp/seed_promotions.php ]; then
    echo "Running promotion seed script..."
    $DRUSH php:script /tmp/seed_promotions.php 2>&1
fi

# Create customer accounts
echo "Creating customer accounts..."
$DRUSH user:create johndoe --mail="john.doe@example.com" --password="Customer123!" 2>&1 || true
$DRUSH user:create janesmith --mail="jane.smith@example.com" --password="Customer123!" 2>&1 || true
$DRUSH user:create mikewilson --mail="mike.wilson@example.com" --password="Customer123!" 2>&1 || true

echo "Data seeding complete!"

# ============================================================
# 5b. Create public product catalog view at /products
# ============================================================
echo "Creating public product catalog view..."
$DRUSH php:eval '
use Drupal\views\Entity\View;

// Delete existing view if present so we can recreate it
$existing = View::load("product_catalog");
if ($existing) {
    $existing->delete();
    echo "Deleted old product_catalog view\n";
}

// Create a view that renders products as entities (includes Add to Cart form)
$view = View::create([
    "id" => "product_catalog",
    "label" => "Product Catalog",
    "module" => "views",
    "description" => "Public storefront product listing with Add to Cart",
    "tag" => "",
    "base_table" => "commerce_product_field_data",
    "base_field" => "product_id",
    "display" => [
        "default" => [
            "display_plugin" => "default",
            "id" => "default",
            "display_title" => "Default",
            "position" => 0,
            "display_options" => [
                "access" => ["type" => "none", "options" => []],
                "cache" => ["type" => "tag", "options" => []],
                "query" => ["type" => "views_query", "options" => ["disable_sql_rewrite" => false]],
                "pager" => ["type" => "full", "options" => ["items_per_page" => 20]],
                "style" => ["type" => "default"],
                "row" => [
                    "type" => "entity:commerce_product",
                    "options" => ["view_mode" => "default"],
                ],
                "filters" => [
                    "status" => [
                        "id" => "status",
                        "table" => "commerce_product_field_data",
                        "field" => "status",
                        "value" => "1",
                        "plugin_id" => "boolean",
                    ],
                ],
                "sorts" => [
                    "title" => [
                        "id" => "title",
                        "table" => "commerce_product_field_data",
                        "field" => "title",
                        "order" => "ASC",
                        "plugin_id" => "standard",
                    ],
                ],
                "title" => "Products",
            ],
        ],
        "page_1" => [
            "display_plugin" => "page",
            "id" => "page_1",
            "display_title" => "Page",
            "position" => 1,
            "display_options" => [
                "path" => "products",
            ],
        ],
    ],
]);
$view->save();
echo "Product catalog view created at /products (rendered entities with Add to Cart)\n";
' 2>&1

# Grant anonymous users permission to view products and use the cart
echo "Granting storefront permissions to anonymous users..."
$DRUSH role:perm:add anonymous \
    "view commerce_product,access cart" 2>&1 || true
$DRUSH role:perm:add authenticated \
    "view commerce_product,access cart,access checkout" 2>&1 || true

# ============================================================
# 6. Fix permissions and clear caches
# ============================================================
echo "Fixing permissions..."
chown -R www-data:www-data "$DRUPAL_DIR/web"
chmod -R 755 "$DRUPAL_DIR/web"
chmod -R 777 "$DRUPAL_DIR/web/sites/default/files" 2>/dev/null || true

$DRUSH cr 2>&1

# ============================================================
# 7. Restart Apache
# ============================================================
echo ""
echo "Restarting Apache..."
systemctl restart apache2

# Wait for Drupal to be accessible
wait_for_drupal 120

# ============================================================
# 8. Create utility script for database queries
# ============================================================
cat > /usr/local/bin/drupal-db-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against Drupal database (via Docker MariaDB)
docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -e "$1"
DBQUERYEOF
chmod +x /usr/local/bin/drupal-db-query

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

// Set homepage to Drupal admin
user_pref("browser.startup.homepage", "http://localhost/admin/commerce");
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
cat > /home/ga/Desktop/DrupalCommerce.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Drupal Commerce Admin
Comment=Drupal Commerce Store Administration
Exec=firefox http://localhost/admin/commerce
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/DrupalCommerce.desktop
chmod +x /home/ga/Desktop/DrupalCommerce.desktop

# ============================================================
# 10. Launch Firefox using Drush one-time login link
# ============================================================
echo "Generating one-time login link..."
LOGIN_URL=$($DRUSH uli --uri=http://localhost --no-browser --uid=1 2>/dev/null)

if [ -n "$LOGIN_URL" ]; then
    # Append destination to go straight to Commerce admin after login
    LOGIN_DEST="${LOGIN_URL}?destination=admin/commerce"
    echo "Login URL generated: $LOGIN_DEST"
    su - ga -c "DISPLAY=:1 firefox '$LOGIN_DEST' > /tmp/firefox_drupal.log 2>&1 &"
else
    echo "WARNING: Could not generate login link, launching admin page directly"
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/admin/commerce' > /tmp/firefox_drupal.log 2>&1 &"
fi

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

    # Wait for Drupal admin page to fully render
    echo "Waiting for Drupal admin page to fully render..."
    PAGE_LOADED=false

    for i in {1..60}; do
        WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
        if echo "$WINDOW_TITLE" | grep -qi "commerce\|drupal\|store\|dashboard"; then
            PAGE_LOADED=true
            echo "Drupal Commerce page detected in window title after ${i}s"
            echo "Window title: $WINDOW_TITLE"
            break
        fi
        sleep 1
    done

    if [ "$PAGE_LOADED" = false ]; then
        echo "WARNING: Drupal Commerce page title not detected after 60s"
        echo "Current window title: $(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i firefox)"
        # Try navigating to Commerce admin
        echo "Attempting to navigate to Commerce admin..."
        DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
        sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers "http://localhost/admin/commerce" 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 10
    fi

    # Additional wait for page rendering
    echo "Waiting additional 10s for page rendering..."
    sleep 10

    # Take verification screenshot
    echo "Taking verification screenshot..."
    DISPLAY=:1 import -window root /tmp/setup_verification.png 2>/dev/null || true

    # Log final window state
    echo "Final window list:"
    DISPLAY=:1 wmctrl -l 2>/dev/null || true
fi

echo ""
echo "=== Drupal Commerce Setup Complete ==="
echo ""
echo "Drupal Commerce store is running at: $DRUPAL_URL"
echo "Admin panel: ${DRUPAL_URL}admin/commerce"
echo ""
echo "Login Credentials:"
echo "  Admin: ${ADMIN_USER} / ${ADMIN_PASS}"
echo ""
echo "Pre-loaded Data:"
echo "  - Default store: Urban Electronics (San Francisco, CA)"
echo "  - 12 products (electronics: headphones, laptops, TVs, mice, keyboards, SSDs, etc.)"
echo "  - 3 promotions/coupons (WELCOME10, SAVE25, Electronics 15% Off)"
echo "  - 3 customer accounts (johndoe, janesmith, mikewilson)"
echo ""
echo "Database access (via Docker):"
echo "  drupal-db-query \"SELECT COUNT(*) FROM commerce_product_field_data\""
echo ""
