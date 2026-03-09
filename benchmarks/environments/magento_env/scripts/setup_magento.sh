#!/bin/bash
# Magento Setup Script (post_start hook)
# Starts MariaDB + Elasticsearch via Docker, runs Magento installer,
# seeds initial data via REST API, launches Firefox
#
# Default admin credentials: admin / Admin1234!

echo "=== Setting up Magento Open Source ==="

# Allow Composer to run as root
export COMPOSER_ALLOW_SUPERUSER=1

# Configuration
MAGENTO_DIR="/var/www/html/magento"
MAGENTO_URL="http://localhost/"
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
ADMIN_EMAIL="admin@example.com"
ADMIN_FIRSTNAME="Magento"
ADMIN_LASTNAME="Admin"
DB_HOST="127.0.0.1"
DB_PORT="3306"
DB_NAME="magento"
DB_USER="magento"
DB_PASS="magentopass"
ADMIN_URI="admin"

# Function to wait for MariaDB to be ready
wait_for_mariadb() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for MariaDB to be ready..."

    while [ $elapsed -lt $timeout ]; do
        if docker exec magento-mariadb mysqladmin ping -h localhost -uroot -prootpass 2>/dev/null | grep -q "alive"; then
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

# Function to wait for Elasticsearch to be ready
wait_for_elasticsearch() {
    local timeout=${1:-180}
    local elapsed=0

    echo "Waiting for Elasticsearch to be ready..."

    while [ $elapsed -lt $timeout ]; do
        if curl -s http://localhost:9200/_cluster/health 2>/dev/null | grep -q '"status"'; then
            echo "Elasticsearch is ready after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting for Elasticsearch... ${elapsed}s"
    done

    echo "WARNING: Elasticsearch readiness check timed out after ${timeout}s"
    return 1
}

# Function to wait for Magento web to be ready
wait_for_magento() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for Magento web interface to be ready..."

    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$MAGENTO_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            echo "Magento web is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done

    echo "WARNING: Magento readiness check timed out after ${timeout}s"
    return 1
}

# ============================================================
# 1. Start MariaDB + Elasticsearch via Docker Compose
# ============================================================
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/magento
cp /workspace/config/docker-compose.yml /home/ga/magento/
chown -R ga:ga /home/ga/magento

echo "Starting MariaDB and Elasticsearch containers..."
cd /home/ga/magento
docker-compose pull
docker-compose up -d

# Wait for services to be ready
wait_for_mariadb 120
wait_for_elasticsearch 180

echo "Docker container status:"
docker-compose ps

# ============================================================
# 2. Install Magento via CLI
# ============================================================
echo ""
echo "Running Magento CLI installer..."

# Ensure correct permissions for installation
chown -R www-data:www-data "$MAGENTO_DIR"
chmod -R 755 "$MAGENTO_DIR"
chmod -R 777 "$MAGENTO_DIR/var"
chmod -R 777 "$MAGENTO_DIR/generated"
chmod -R 777 "$MAGENTO_DIR/pub/static"
chmod -R 777 "$MAGENTO_DIR/app/etc"

cd "$MAGENTO_DIR"

# Run Magento setup:install
php bin/magento setup:install \
    --base-url="$MAGENTO_URL" \
    --db-host="$DB_HOST:$DB_PORT" \
    --db-name="$DB_NAME" \
    --db-user="$DB_USER" \
    --db-password="$DB_PASS" \
    --admin-firstname="$ADMIN_FIRSTNAME" \
    --admin-lastname="$ADMIN_LASTNAME" \
    --admin-email="$ADMIN_EMAIL" \
    --admin-user="$ADMIN_USER" \
    --admin-password="$ADMIN_PASS" \
    --language=en_US \
    --currency=USD \
    --timezone=America/New_York \
    --use-rewrites=1 \
    --search-engine=elasticsearch7 \
    --elasticsearch-host=localhost \
    --elasticsearch-port=9200 \
    --backend-frontname="$ADMIN_URI" \
    --cleanup-database 2>&1

INSTALL_EXIT=$?
if [ $INSTALL_EXIT -ne 0 ]; then
    echo "WARNING: Magento installer exited with code $INSTALL_EXIT"
    echo "Checking if env.php exists..."
    if [ -f "$MAGENTO_DIR/app/etc/env.php" ]; then
        echo "env.php exists - Magento may already be installed"
    else
        echo "ERROR: env.php not found. Installation failed."
        exit 1
    fi
fi

# ============================================================
# 3. Disable 2FA, compile, and deploy
# ============================================================
echo ""
echo "Configuring Magento modules..."

cd "$MAGENTO_DIR"

# Disable two-factor auth for easier admin login in testing
php bin/magento module:disable Magento_AdminAdobeImsTwoFactorAuth 2>&1 || true
php bin/magento module:disable Magento_TwoFactorAuth 2>&1 || true

# Run setup:upgrade after module changes
echo "Running setup:upgrade..."
php -d memory_limit=2G bin/magento setup:upgrade 2>&1

# Set developer mode for easier debugging
php bin/magento deploy:mode:set developer 2>&1

# Compile DI (must run after all module changes)
echo "Compiling Magento DI..."
php -d memory_limit=2G bin/magento setup:di:compile 2>&1 || echo "DI compile had warnings"

# Deploy static content
echo "Deploying static content..."
php -d memory_limit=2G bin/magento setup:static-content:deploy -f en_US 2>&1 || echo "Static content deploy had warnings"

# Clear cache
php bin/magento cache:clean 2>&1
php bin/magento cache:flush 2>&1

# ============================================================
# 4. Fix permissions (MUST come after compile)
# ============================================================
echo "Fixing permissions..."
chown -R www-data:www-data "$MAGENTO_DIR"
chmod -R 777 "$MAGENTO_DIR/var"
chmod -R 777 "$MAGENTO_DIR/generated"
chmod -R 777 "$MAGENTO_DIR/pub/static"
chmod -R 777 "$MAGENTO_DIR/pub/media"
chmod -R 777 "$MAGENTO_DIR/app/etc"

# ============================================================
# 5. Start Apache
# ============================================================
echo ""
echo "Starting Apache..."
systemctl restart apache2

# Wait for Magento to be accessible
wait_for_magento 120

# ============================================================
# 6. Seed Initial Data via REST API
# ============================================================
echo ""
echo "Seeding initial data via Magento REST API..."

# Seed data using Python + REST API (avoids need for repo.magento.com auth keys)
python3 << 'SEEDEOF'
import urllib.request
import json
import sys

BASE_URL = "http://localhost"

def api_request(method, endpoint, data=None, token=None):
    """Make a Magento REST API request."""
    url = f"{BASE_URL}/rest/V1/{endpoint}"
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req)
        return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        err_body = e.read().decode()
        print(f"  API error {e.code} for {endpoint}: {err_body[:200]}")
        return None
    except Exception as e:
        print(f"  Error for {endpoint}: {e}")
        return None

# Get admin token
print("Getting admin token...")
token = api_request("POST", "integration/admin/token",
                    {"username": "admin", "password": "Admin1234!"})
if not token:
    print("ERROR: Could not get admin token. Skipping data seeding.")
    sys.exit(0)
print(f"  Token obtained")

# Create categories
print("Creating categories...")
categories = [
    {"name": "Electronics", "is_active": True, "include_in_menu": True},
    {"name": "Clothing", "is_active": True, "include_in_menu": True},
    {"name": "Home & Garden", "is_active": True, "include_in_menu": True},
    {"name": "Sports", "is_active": True, "include_in_menu": True},
]
cat_ids = {}
for cat in categories:
    result = api_request("POST", "categories", {
        "category": {
            "parent_id": 2,  # Default Category
            "name": cat["name"],
            "is_active": cat["is_active"],
            "include_in_menu": cat["include_in_menu"],
        }
    }, token)
    if result:
        cat_ids[cat["name"]] = result.get("id", 0)
        print(f"  Created category: {cat['name']} (ID: {cat_ids[cat['name']]})")

# Create simple products
print("Creating products...")
products = [
    {"sku": "LAPTOP-001", "name": "Business Laptop Pro", "price": 999.99, "qty": 50, "category": "Electronics"},
    {"sku": "PHONE-001", "name": "Smartphone Ultra", "price": 699.99, "qty": 100, "category": "Electronics"},
    {"sku": "HEADPHONES-001", "name": "Wireless Headphones", "price": 149.99, "qty": 200, "category": "Electronics"},
    {"sku": "TSHIRT-001", "name": "Classic Cotton T-Shirt", "price": 24.99, "qty": 500, "category": "Clothing"},
    {"sku": "JEANS-001", "name": "Slim Fit Jeans", "price": 49.99, "qty": 300, "category": "Clothing"},
    {"sku": "JACKET-001", "name": "Winter Jacket", "price": 129.99, "qty": 150, "category": "Clothing"},
    {"sku": "LAMP-001", "name": "LED Desk Lamp", "price": 34.99, "qty": 400, "category": "Home & Garden"},
    {"sku": "PILLOW-001", "name": "Memory Foam Pillow", "price": 39.99, "qty": 350, "category": "Home & Garden"},
    {"sku": "YOGA-001", "name": "Yoga Mat Premium", "price": 29.99, "qty": 250, "category": "Sports"},
    {"sku": "BOTTLE-001", "name": "Insulated Water Bottle", "price": 19.99, "qty": 600, "category": "Sports"},
]
for prod in products:
    cat_id = cat_ids.get(prod["category"], 2)
    result = api_request("POST", "products", {
        "product": {
            "sku": prod["sku"],
            "name": prod["name"],
            "price": prod["price"],
            "status": 1,
            "visibility": 4,
            "type_id": "simple",
            "attribute_set_id": 4,
            "weight": 1.0,
            "extension_attributes": {
                "stock_item": {
                    "qty": prod["qty"],
                    "is_in_stock": True
                },
                "category_links": [
                    {"position": 0, "category_id": str(cat_id)}
                ]
            }
        }
    }, token)
    if result:
        print(f"  Created product: {prod['name']} (SKU: {prod['sku']})")

# Create customers
print("Creating customers...")
customers = [
    {"email": "john.doe@example.com", "firstname": "John", "lastname": "Doe"},
    {"email": "jane.smith@example.com", "firstname": "Jane", "lastname": "Smith"},
    {"email": "mike.wilson@example.com", "firstname": "Mike", "lastname": "Wilson"},
]
for cust in customers:
    result = api_request("POST", "customers", {
        "customer": {
            "email": cust["email"],
            "firstname": cust["firstname"],
            "lastname": cust["lastname"],
            "group_id": 1,
            "store_id": 1,
            "website_id": 1
        },
        "password": "Customer123!"
    }, token)
    if result:
        print(f"  Created customer: {cust['firstname']} {cust['lastname']} ({cust['email']})")

print("Data seeding complete!")
SEEDEOF

# ============================================================
# 7. Reindex (so seeded products appear in search/catalog)
# ============================================================
echo "Running Magento indexer..."
cd "$MAGENTO_DIR"
php bin/magento indexer:reindex 2>&1 || echo "Indexer had some issues"

# ============================================================
# 8. Set up Firefox profile for user 'ga'
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

// Set homepage to Magento storefront
user_pref("browser.startup.homepage", "http://localhost/");
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
cat > /home/ga/Desktop/Magento.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Magento Admin
Comment=Magento Open Source Administration
Exec=firefox http://localhost/admin
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/Magento.desktop
chmod +x /home/ga/Desktop/Magento.desktop

# Create utility script for database queries
cat > /usr/local/bin/magento-db-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against Magento database (via Docker MariaDB)
docker exec magento-mariadb mysql -u magento -pmagentopass magento -e "$1"
DBQUERYEOF
chmod +x /usr/local/bin/magento-db-query

# ============================================================
# 9. Launch Firefox and Log Into Admin Panel
# ============================================================
echo "Launching Firefox with Magento admin panel..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/admin' > /tmp/firefox_magento.log 2>&1 &"

# Wait for Firefox window
sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|magento"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    sleep 3
    # Maximize Firefox window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi

    # Wait for the login page to fully load (Magento admin pages are JavaScript-heavy)
    echo "Waiting for admin login page to load..."
    sleep 20

    # Take screenshot before login attempt
    DISPLAY=:1 scrot /tmp/before_login_screenshot.png 2>/dev/null || true

    # ============================================================
    # ROBUST LOGIN VERIFICATION FUNCTION
    # Uses multiple methods to verify we are on the dashboard
    # ============================================================
    verify_login_success() {
        echo "  Verifying login status..."

        # Method 1: Check window title for "Dashboard" (most reliable)
        WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
        echo "    Window title: $WINDOW_TITLE"

        if echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
            echo "    SUCCESS: Dashboard detected in window title"
            return 0
        fi

        # Method 2: Check if title still shows login indicators
        if echo "$WINDOW_TITLE" | grep -qi "sign in\|login\|welcome.*please"; then
            echo "    FAIL: Login page detected in window title"
            return 1
        fi

        # Method 3: Use xdotool to get the active window name
        ACTIVE_NAME=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
        echo "    Active window name: $ACTIVE_NAME"

        if echo "$ACTIVE_NAME" | grep -qi "dashboard"; then
            echo "    SUCCESS: Dashboard detected in active window"
            return 0
        fi

        if echo "$ACTIVE_NAME" | grep -qi "sign in\|login\|welcome"; then
            echo "    FAIL: Login page detected in active window"
            return 1
        fi

        # Method 4: Check for dashboard-specific elements using Firefox JavaScript console
        # The dashboard page has specific elements we can detect
        # We use xdotool to open DevTools, run a check, and close it
        echo "    Checking page content via JavaScript..."

        # Take a screenshot and use OCR-like detection by checking pixel regions
        # The dashboard has a dark sidebar (~50px from left) while login page has white background
        DISPLAY=:1 scrot /tmp/verify_screenshot.png 2>/dev/null || true

        # Use ImageMagick to check pixel color at specific locations
        # Dashboard sidebar is dark (around x=30), login page is light/white
        if command -v convert &>/dev/null; then
            # Get pixel color at (30, 400) - should be dark blue (#1a1a2e or similar) on dashboard
            PIXEL_COLOR=$(DISPLAY=:1 convert /tmp/verify_screenshot.png -crop 1x1+30+400 -format "%[hex:p{0,0}]" info: 2>/dev/null || echo "FFFFFF")
            echo "    Left sidebar pixel color: #$PIXEL_COLOR"

            # Dark sidebar colors start with low hex values (00-4F for R component)
            # Extract red component (first 2 hex chars)
            RED_COMPONENT=$(echo "$PIXEL_COLOR" | cut -c1-2)
            RED_DEC=$((16#$RED_COMPONENT)) 2>/dev/null || RED_DEC=255

            if [ "$RED_DEC" -lt 80 ]; then
                echo "    SUCCESS: Dark sidebar detected (dashboard)"
                return 0
            else
                echo "    INCONCLUSIVE: Sidebar color suggests possible login page"
            fi
        fi

        # Method 5: Check URL contains "dashboard"
        # This requires getting the URL from Firefox, which is tricky
        # We'll rely on the above methods

        # If we reach here, we couldn't definitively determine the state
        # Be conservative and return failure
        echo "    FAIL: Could not verify dashboard (conservative approach)"
        return 1
    }

    # Function to perform the login action
    perform_login() {
        local attempt=$1
        echo "Login attempt $attempt..."

        # Focus the Firefox window
        DISPLAY=:1 wmctrl -a "firefox" 2>/dev/null || DISPLAY=:1 wmctrl -a "Mozilla" 2>/dev/null || true
        sleep 1

        # Press Escape to ensure no popups or URL bar focus
        DISPLAY=:1 xdotool key Escape
        sleep 0.3

        # CUA-verified coordinates at 1920x1080 resolution:
        # Username field: (996, 605)
        # Password field: (996, 693)
        # Sign In button: (896, 792)

        # Click on username field
        echo "  Clicking username field..."
        DISPLAY=:1 xdotool mousemove 996 605
        sleep 0.3
        DISPLAY=:1 xdotool click 1
        sleep 0.3
        DISPLAY=:1 xdotool click 1
        sleep 0.3

        # Clear and type username
        DISPLAY=:1 xdotool key ctrl+a
        sleep 0.2
        DISPLAY=:1 xdotool type --delay 50 --clearmodifiers "$ADMIN_USER"
        sleep 0.5

        # Click on password field
        echo "  Clicking password field..."
        DISPLAY=:1 xdotool mousemove 996 693
        sleep 0.3
        DISPLAY=:1 xdotool click 1
        sleep 0.3

        # Type password
        DISPLAY=:1 xdotool type --delay 50 --clearmodifiers "$ADMIN_PASS"
        sleep 0.5

        # Take screenshot showing filled credentials
        DISPLAY=:1 scrot /tmp/credentials_filled_attempt${attempt}.png 2>/dev/null || true

        # Click Sign In button
        echo "  Clicking Sign In button..."
        DISPLAY=:1 xdotool mousemove 896 792
        sleep 0.3
        DISPLAY=:1 xdotool click 1
        sleep 1

        # Press Enter as backup submission method
        DISPLAY=:1 xdotool key Return

        # Wait for page to load (Magento is slow)
        echo "  Waiting for page response..."
        sleep 20
    }

    # Function to perform login with alternative coordinates
    perform_login_alt() {
        local attempt=$1
        echo "Login attempt $attempt (alternative coordinates)..."

        DISPLAY=:1 wmctrl -a "firefox" 2>/dev/null || DISPLAY=:1 wmctrl -a "Mozilla" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key Escape
        sleep 0.3

        # Alternative coordinates (slightly adjusted for variance)
        # These target the same fields but with small offsets

        # Username field (center of form, adjusted)
        echo "  Clicking username field (alt)..."
        DISPLAY=:1 xdotool mousemove 755 459
        sleep 0.3
        DISPLAY=:1 xdotool click 1
        sleep 0.3
        DISPLAY=:1 xdotool click 1
        sleep 0.3

        DISPLAY=:1 xdotool key ctrl+a
        sleep 0.2
        DISPLAY=:1 xdotool type --delay 50 --clearmodifiers "$ADMIN_USER"
        sleep 0.5

        # Password field (adjusted)
        echo "  Clicking password field (alt)..."
        DISPLAY=:1 xdotool mousemove 755 527
        sleep 0.3
        DISPLAY=:1 xdotool click 1
        sleep 0.3

        DISPLAY=:1 xdotool type --delay 50 --clearmodifiers "$ADMIN_PASS"
        sleep 0.5

        DISPLAY=:1 scrot /tmp/credentials_filled_alt_attempt${attempt}.png 2>/dev/null || true

        # Sign In button (adjusted)
        echo "  Clicking Sign In button (alt)..."
        DISPLAY=:1 xdotool mousemove 678 601
        sleep 0.3
        DISPLAY=:1 xdotool click 1
        sleep 1

        DISPLAY=:1 xdotool key Return
        sleep 20
    }

    # Function to dismiss popups on the dashboard
    dismiss_popups() {
        echo "Dismissing any popups..."

        # Adobe data collection popup - "Don't Allow" button
        # CUA-verified at 1920x1080: (1194, 653)
        DISPLAY=:1 xdotool mousemove 1194 653
        sleep 0.3
        DISPLAY=:1 xdotool click 1
        sleep 1

        # Press Escape multiple times to close any modals
        DISPLAY=:1 xdotool key Escape
        sleep 0.5
        DISPLAY=:1 xdotool key Escape
        sleep 0.5

        # Click on dashboard background to deselect
        DISPLAY=:1 xdotool mousemove 400 400
        sleep 0.2
        DISPLAY=:1 xdotool click 1
        sleep 1
    }

    # ============================================================
    # MAIN LOGIN LOOP WITH RETRY AND VERIFICATION
    # ============================================================
    MAX_LOGIN_ATTEMPTS=5
    LOGIN_SUCCESS=false

    echo ""
    echo "Starting Magento admin login process..."
    echo "Will attempt up to $MAX_LOGIN_ATTEMPTS times with verification"
    echo ""

    for attempt in $(seq 1 $MAX_LOGIN_ATTEMPTS); do
        echo "=========================================="
        echo "LOGIN ATTEMPT $attempt of $MAX_LOGIN_ATTEMPTS"
        echo "=========================================="

        # Perform login
        if [ $attempt -le 2 ]; then
            perform_login $attempt
        else
            # Use alternative coordinates for later attempts
            perform_login_alt $attempt
        fi

        # Wait additional time for JavaScript to render
        sleep 5

        # Take verification screenshot
        DISPLAY=:1 scrot /tmp/login_verify_attempt${attempt}.png 2>/dev/null || true

        # Verify if login succeeded
        if verify_login_success; then
            echo ""
            echo ">>> LOGIN VERIFIED SUCCESSFUL <<<"
            echo ""
            LOGIN_SUCCESS=true

            # Dismiss any popups on the dashboard
            dismiss_popups

            break
        else
            echo ""
            echo "Login attempt $attempt FAILED - will retry"
            echo ""

            if [ $attempt -lt $MAX_LOGIN_ATTEMPTS ]; then
                # Refresh the page before next attempt
                echo "Refreshing page..."
                DISPLAY=:1 xdotool key F5
                sleep 15
            fi
        fi
    done

    # Final verification and screenshot
    DISPLAY=:1 scrot /tmp/admin_final_state.png 2>/dev/null || true

    if [ "$LOGIN_SUCCESS" = true ]; then
        echo ""
        echo "============================================"
        echo "LOGIN AUTOMATION COMPLETED SUCCESSFULLY"
        echo "============================================"
    else
        echo ""
        echo "============================================"
        echo "WARNING: LOGIN AUTOMATION MAY HAVE FAILED"
        echo "Agent may need to log in manually"
        echo "Credentials: admin / Admin1234!"
        echo "============================================"
    fi

    echo "Final window: $(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | head -1)"
fi

echo ""
echo "=== Magento Setup Complete ==="
echo ""
echo "Magento is running at: $MAGENTO_URL"
echo "Admin panel: ${MAGENTO_URL}${ADMIN_URI}"
echo ""
echo "Login Credentials:"
echo "  Admin: ${ADMIN_USER} / ${ADMIN_PASS}"
echo ""
echo "Pre-loaded Data:"
echo "  - 10 products across 4 categories (Electronics, Clothing, Home & Garden, Sports)"
echo "  - 4 custom categories + Default Category"
echo "  - 3 customers (John Doe, Jane Smith, Mike Wilson)"
echo "  - Luma theme with responsive storefront"
echo ""
echo "Database access (via Docker):"
echo "  magento-db-query \"SELECT COUNT(*) FROM catalog_product_entity\""
echo ""
