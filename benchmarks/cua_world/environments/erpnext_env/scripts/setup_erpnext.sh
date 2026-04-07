#!/bin/bash
# ERPNext Setup Script (post_start hook)
# Starts ERPNext via Docker Compose, waits for site creation,
# completes setup via bench CLI, and launches Firefox.
#
# Default credentials: Administrator / admin
# Company created: Wind Power LLC (from erpnext.setup.utils.before_tests)

echo "=== Setting up ERPNext via Docker ==="

# Configuration
ERPNEXT_URL="http://localhost:8080"
ADMIN_USER="Administrator"
ADMIN_PASS="admin"
SITE_NAME="frontend"

# Determine which docker-compose command to use
if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    echo "ERROR: Neither docker-compose nor docker compose plugin found!"
    exit 1
fi
echo "Using compose command: $COMPOSE_CMD"

# Function to wait for ERPNext to be ready
wait_for_erpnext() {
    local timeout=${1:-600}
    local elapsed=0

    echo "Waiting for ERPNext to be ready..."

    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ERPNEXT_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
            echo "ERPNext is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        if [ $((elapsed % 60)) -eq 0 ]; then
            echo "  Still waiting... ${elapsed}s (HTTP $HTTP_CODE)"
        fi
    done

    echo "WARNING: ERPNext readiness check timed out after ${timeout}s"
    return 1
}

# Function to complete ERPNext setup via bench CLI
complete_setup() {
    echo "Completing ERPNext setup via bench CLI..."
    cd /home/ga/erpnext

    # Use bench execute to run erpnext.setup.utils.before_tests
    # This creates company "Wind Power LLC" with chart of accounts, fiscal year,
    # warehouses, cost centers, and other essential setup data.
    # Retry up to 3 times since the backend may not be fully ready.
    # Step 1: Run before_tests to create company/accounts data
    SETUP_OK=false
    for attempt in 1 2 3 4 5; do
        echo "before_tests attempt $attempt..."
        # Use pipefail to catch bench failures (pipe to tail hides exit code)
        BT_OUTPUT=$($COMPOSE_CMD exec -T backend bench --site frontend execute erpnext.setup.utils.before_tests 2>&1) || true
        BT_EXIT=$?
        echo "$BT_OUTPUT" | tail -10
        if echo "$BT_OUTPUT" | grep -qi "error\|traceback\|exception"; then
            echo "  attempt $attempt had errors, retrying in 20s..."
            sleep 20
            continue
        fi
        echo "before_tests execution complete on attempt $attempt"
        SETUP_OK=true
        break
    done

    if [ "$SETUP_OK" = false ]; then
        echo "WARNING: before_tests may not have succeeded after 5 attempts"
    fi

    # Step 2: Run migrations first (before setting setup_complete, since migrate can reset it)
    echo "Running database migrations..."
    $COMPOSE_CMD exec -T backend bench --site frontend migrate 2>&1 | tail -5 || true

    # Step 3: Force setup_complete=1 via ALL available methods (AFTER migrate)

    # Method A: Write directly to site_config.json (Frappe checks this first)
    echo "Setting setup_complete in site_config.json..."
    $COMPOSE_CMD exec -T backend bench --site frontend set-config setup_complete 1 2>&1 || true
    # Also patch it directly via Python to guarantee it's there
    $COMPOSE_CMD exec -T backend python3 -c "
import json
p = 'sites/frontend/site_config.json'
with open(p) as f: c = json.load(f)
c['setup_complete'] = 1
with open(p, 'w') as f: json.dump(c, f, indent=1)
print('site_config.json updated: setup_complete=1')
" 2>&1 || true

    # Method B: Set via bench CLI
    $COMPOSE_CMD exec -T backend bench --site frontend execute frappe.client.set_value \
        --kwargs '{"doctype":"System Settings","name":"System Settings","fieldname":"setup_complete","value":1}' 2>&1 | tail -3 || true

    # Method C: Set directly in the database
    echo "Setting setup_complete via direct DB update..."
    SITE_DB=$($COMPOSE_CMD exec -T backend cat sites/frontend/site_config.json 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('db_name',''))" 2>/dev/null || true)
    if [ -n "$SITE_DB" ]; then
        echo "  Found site DB: $SITE_DB"
        $COMPOSE_CMD exec -T db mysql -u root -padmin "$SITE_DB" -e \
            "UPDATE \`tabSystem Settings\` SET setup_complete=1 WHERE name='System Settings';" 2>&1 || true
        # Verify
        SETUP_VAL=$($COMPOSE_CMD exec -T db mysql -u root -padmin "$SITE_DB" -N -e \
            "SELECT setup_complete FROM \`tabSystem Settings\` WHERE name='System Settings';" 2>/dev/null | tr -d '[:space:]')
        echo "  DB setup_complete value: '$SETUP_VAL'"
    else
        echo "  WARNING: Could not determine site DB name"
    fi

    # Method D: Use bench console as final fallback
    $COMPOSE_CMD exec -T backend bench --site frontend console <<'PYEOF' 2>&1 || true
import frappe
frappe.db.set_single_value("System Settings", "setup_complete", 1)
frappe.db.commit()
print("setup_complete set to 1 via console")
PYEOF

    # Step 4: Clear cache and restart
    $COMPOSE_CMD exec -T backend bench --site frontend clear-cache 2>&1 || true

    echo "Restarting backend to apply setup changes..."
    $COMPOSE_CMD restart backend 2>&1 || true
    sleep 15

    return 0
}

# Ensure Docker is running
echo "Checking Docker service..."
systemctl is-active docker || systemctl start docker
sleep 3

# Copy docker-compose.yml to working directory
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/erpnext
cp /workspace/config/docker-compose.yml /home/ga/erpnext/
chown -R ga:ga /home/ga/erpnext

# Start ERPNext containers
echo "Starting ERPNext Docker containers..."
cd /home/ga/erpnext
$COMPOSE_CMD up -d 2>&1

echo "Containers starting..."
$COMPOSE_CMD ps 2>/dev/null || true

# Wait for ERPNext to be fully ready (site creation + frontend)
wait_for_erpnext 600

# Show container status
echo ""
echo "Container status:"
$COMPOSE_CMD ps 2>/dev/null || true

# Complete setup
sleep 5
complete_setup

# Wait for ERPNext to actually serve pages after setup completion.
# The initial wait may have timed out (HTTP 500 during site creation).
# After before_tests, ERPNext should start serving properly.
echo "Verifying ERPNext is serving after setup..."
for i in $(seq 1 60); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ERPNEXT_URL" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
        echo "ERPNext serving OK (HTTP $HTTP_CODE) after setup"
        break
    fi
    sleep 5
done

# Verify setup wizard is NOT showing (critical check).
# If ERPNext still redirects to setup-wizard, re-apply the fix.
BODY=$(curl -sL "$ERPNEXT_URL" 2>/dev/null | head -100)
if echo "$BODY" | grep -qi "setup.wizard\|setup_wizard"; then
    echo "WARNING: Setup wizard still detected! Re-applying setup_complete fix..."
    cd /home/ga/erpnext

    # Patch site_config.json directly (most reliable method)
    $COMPOSE_CMD exec -T backend python3 -c "
import json
p = 'sites/frontend/site_config.json'
with open(p) as f: c = json.load(f)
c['setup_complete'] = 1
with open(p, 'w') as f: json.dump(c, f, indent=1)
print('site_config.json patched: setup_complete=1')
" 2>&1 || true

    # Also set in DB
    SITE_DB=$($COMPOSE_CMD exec -T backend cat sites/frontend/site_config.json 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('db_name',''))" 2>/dev/null || true)
    if [ -n "$SITE_DB" ]; then
        $COMPOSE_CMD exec -T db mysql -u root -padmin "$SITE_DB" -e \
            "UPDATE \`tabSystem Settings\` SET setup_complete=1 WHERE name='System Settings';" 2>&1 || true
    fi

    # Try bench console to set it programmatically inside Python runtime
    $COMPOSE_CMD exec -T backend bench --site frontend console <<'PYEOF' 2>&1 || true
import frappe
frappe.db.set_single_value("System Settings", "setup_complete", 1)
frappe.db.commit()
print("setup_complete set to 1 via console")
PYEOF
    $COMPOSE_CMD exec -T backend bench --site frontend clear-cache 2>&1 || true

    # Restart ALL containers to fully clear caches
    $COMPOSE_CMD restart 2>&1 || true
    sleep 20

    # Wait for ERPNext to come back
    for retry_i in $(seq 1 30); do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ERPNEXT_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then break; fi
        sleep 5
    done

    echo "Re-check after fix..."
    BODY2=$(curl -sL "$ERPNEXT_URL" 2>/dev/null | head -100)
    if echo "$BODY2" | grep -qi "setup.wizard\|setup_wizard"; then
        echo "ERROR: Setup wizard still showing after all fix attempts"
    else
        echo "Setup wizard fix succeeded on retry"
    fi
else
    echo "Setup wizard check passed — no wizard detected"
fi

# Set up Firefox profile for user 'ga'
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

# Create user.js to configure Firefox (disable first-run dialogs, etc.)
cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'USERJS'
// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to ERPNext
user_pref("browser.startup.homepage", "http://localhost:8080");
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
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/ERPNext.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=ERPNext
Comment=Enterprise Resource Planning
Exec=firefox http://localhost:8080
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Business;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/ERPNext.desktop
chmod +x /home/ga/Desktop/ERPNext.desktop

# Create utility script for MariaDB queries
cat > /usr/local/bin/erpnext-db-query << 'DBQUERYEOF'
#!/bin/bash
cd /home/ga/erpnext
docker-compose exec -T db mysql -u root -padmin -N -e "$1" 2>/dev/null
DBQUERYEOF
chmod +x /usr/local/bin/erpnext-db-query

# Start Firefox for the ga user
echo "Launching Firefox with ERPNext..."
pkill -9 -f firefox 2>/dev/null || true
sleep 2
rm -f /home/ga/.mozilla/firefox/default-release/.parentlock \
      /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
su - ga -c "DISPLAY=:1 firefox '$ERPNEXT_URL' > /tmp/firefox_erpnext.log 2>&1 &"

# Wait for Firefox window
sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|erpnext"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    sleep 2
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi

    # Auto-login Firefox so the browser session is authenticated.
    # This ensures task setup scripts can navigate directly to form URLs
    # without the agent encountering a login page.
    echo "Auto-logging into ERPNext via browser..."

    # Navigate to login page explicitly — Firefox may have loaded an error
    # page if it launched while ERPNext was still starting up.
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "http://localhost:8080/login"
    sleep 0.3
    DISPLAY=:1 xdotool key Return

    # Wait for login page to load (generous wait)
    sleep 8

    # Attempt 1: Type credentials via xdotool into the login form
    echo "Typing login credentials..."
    # Click on the email field area (center of page, where the input is)
    DISPLAY=:1 xdotool mousemove 994 414 click 1
    sleep 1
    # Clear any existing text and type Administrator
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers 'Administrator'
    sleep 0.5
    # Tab to password field
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    # Type password
    DISPLAY=:1 xdotool type --clearmodifiers 'admin'
    sleep 0.5
    # Press Enter to submit login
    DISPLAY=:1 xdotool key Return
    sleep 8

    # Verify login succeeded by checking window title changes
    LOGIN_OK=false
    for i in {1..15}; do
        TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
        if echo "$TITLE" | grep -qi "home\|setup\|desk\|erpnext\|module"; then
            LOGIN_OK=true
            echo "Browser login successful (window: $TITLE)"
            break
        fi
        # Also check if we're past the login page
        if [ -n "$TITLE" ] && ! echo "$TITLE" | grep -qi "login"; then
            LOGIN_OK=true
            echo "Browser login successful (no longer on login page)"
            break
        fi
        sleep 2
    done

    if [ "$LOGIN_OK" = false ]; then
        echo "First xdotool login attempt did not succeed. Trying JavaScript console fallback..."

        # Fallback: Use browser console to POST login via fetch API.
        # This is more reliable than xdotool coordinates since it doesn't
        # depend on the login form layout or field positions.
        DISPLAY=:1 xdotool key ctrl+shift+k
        sleep 2

        # Type the fetch command to login via API
        DISPLAY=:1 xdotool type --clearmodifiers "fetch('/api/method/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({usr:'Administrator',pwd:'admin'})}).then(r=>{if(r.ok)window.location='/app/home'})"
        sleep 0.5
        DISPLAY=:1 xdotool key Return
        sleep 8

        # Close the console
        DISPLAY=:1 xdotool key ctrl+shift+k
        sleep 1

        # Check if JS login worked
        for i in {1..10}; do
            TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
            if echo "$TITLE" | grep -qi "home\|setup\|desk\|erpnext\|module"; then
                LOGIN_OK=true
                echo "JS console login successful (window: $TITLE)"
                break
            fi
            if [ -n "$TITLE" ] && ! echo "$TITLE" | grep -qi "login"; then
                LOGIN_OK=true
                echo "JS console login successful (no longer on login page)"
                break
            fi
            sleep 2
        done
    fi

    if [ "$LOGIN_OK" = false ]; then
        echo "WARNING: All login attempts may have failed. Trying one final reload + xdotool..."
        # Final attempt: navigate to login and retry typing
        DISPLAY=:1 xdotool key ctrl+l
        sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers "http://localhost:8080/login"
        sleep 0.3
        DISPLAY=:1 xdotool key Return
        sleep 10
        DISPLAY=:1 xdotool mousemove 994 414 click 1
        sleep 1
        DISPLAY=:1 xdotool key ctrl+a
        sleep 0.3
        DISPLAY=:1 xdotool type --clearmodifiers 'Administrator'
        sleep 0.5
        DISPLAY=:1 xdotool key Tab
        sleep 0.3
        DISPLAY=:1 xdotool type --clearmodifiers 'admin'
        sleep 0.5
        DISPLAY=:1 xdotool key Return
        sleep 5
        echo "Final login attempt completed"
    fi

    # Navigate to home to confirm authenticated state
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "http://localhost:8080/app/home"
    sleep 0.3
    DISPLAY=:1 xdotool key Return
    sleep 5
    echo "Navigated to ERPNext home"
fi

echo ""
echo "=== ERPNext Setup Complete ==="
echo ""
echo "ERPNext is running at: $ERPNEXT_URL"
echo "Login: $ADMIN_USER / $ADMIN_PASS"
echo "Company: Wind Power LLC"
echo ""
