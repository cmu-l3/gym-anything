#!/bin/bash
# NOTE: No set -e here — we handle errors explicitly

echo "=== Setting up Virtualmin (post_start) ==="

# ---------------------------------------------------------------
# IDEMPOTENCY CHECK: If domains already exist, only refresh Firefox.
# This handles reloading from savevm checkpoint where everything is
# already configured. Skip the long setup and just ensure Firefox
# is open and logged in.
# ---------------------------------------------------------------
DOMAINS_EXIST=false
if which virtualmin > /dev/null 2>&1; then
    DOMAIN_COUNT=$(virtualmin list-domains --name-only 2>/dev/null | wc -l)
    if [ "$DOMAIN_COUNT" -ge 3 ]; then
        echo "=== Domains already exist ($DOMAIN_COUNT found). Running idempotent refresh. ==="
        DOMAINS_EXIST=true
    fi
fi

if $DOMAINS_EXIST; then
    # Ensure services are running
    for svc in apache2 mariadb named postfix dovecot webmin; do
        systemctl is-active --quiet "$svc" 2>/dev/null || systemctl start "$svc" 2>/dev/null || true
    done
    sleep 3

    # Fix Webmin referrer checking to allow direct URL navigation from address bar
    # (needed for pre_task scripts to navigate to specific Virtualmin pages)
    # Must fix BOTH config AND miniserv.conf
    sed -i 's/^referers_none=1/referers_none=0/' /etc/webmin/config 2>/dev/null || true
    grep -q "^referers_none=" /etc/webmin/config 2>/dev/null || echo "referers_none=0" >> /etc/webmin/config
    sed -i 's/^referers_none=1/referers_none=0/' /etc/webmin/miniserv.conf 2>/dev/null || true
    grep -q "^referers_none=" /etc/webmin/miniserv.conf 2>/dev/null || echo "referers_none=0" >> /etc/webmin/miniserv.conf
    systemctl restart webmin 2>/dev/null || true
    sleep 5

    # Re-launch Firefox if not running
    if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iq "firefox\|mozilla"; then
        su - ga -c "DISPLAY=:1 firefox https://localhost:10000 &" 2>/dev/null
        sleep 12
        DISPLAY=:1 xdotool mousemove 1318 705 click 1 2>/dev/null; sleep 3
        DISPLAY=:1 xdotool mousemove 1251 1008 click 1 2>/dev/null; sleep 5
        DISPLAY=:1 xdotool mousemove 993 384 click 1 2>/dev/null; sleep 0.5
        DISPLAY=:1 xdotool key ctrl+a 2>/dev/null
        DISPLAY=:1 xdotool type --clearmodifiers --delay 30 "root" 2>/dev/null
        DISPLAY=:1 xdotool key Tab 2>/dev/null; sleep 0.3
        DISPLAY=:1 xdotool type --clearmodifiers --delay 30 "GymAnything123!" 2>/dev/null
        DISPLAY=:1 xdotool mousemove 993 511 click 1 2>/dev/null; sleep 8
    fi
    echo "=== Idempotent refresh complete ==="
    exit 0
fi

# ---------------------------------------------------------------
# 1. Wait for Virtualmin background installation to complete
#    The install_virtualmin.sh (pre_start) started the installer
#    in the background. We must wait for it before proceeding.
# ---------------------------------------------------------------
echo "--- Waiting for Virtualmin installation to complete ---"

TIMEOUT=1800  # 30 minutes max
ELAPSED=0
LAST_LOG_SIZE=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check for completion marker
    if [ -f /home/ga/virtualmin-install-done ]; then
        echo "=== Virtualmin installation complete! (marker found at ${ELAPSED}s) ==="
        break
    fi

    # Check if virtualmin command is available
    if which virtualmin > /dev/null 2>&1; then
        echo "=== Virtualmin command available (${ELAPSED}s) ==="
        break
    fi

    # Show progress from install log
    if [ -f /home/ga/virtualmin-install.log ]; then
        NEW_SIZE=$(wc -c < /home/ga/virtualmin-install.log 2>/dev/null || echo 0)
        if [ "$NEW_SIZE" -ne "$LAST_LOG_SIZE" ]; then
            echo "  [${ELAPSED}s] Log size: ${NEW_SIZE} bytes, last lines:"
            tail -3 /home/ga/virtualmin-install.log 2>/dev/null | sed 's/^/    /'
            LAST_LOG_SIZE=$NEW_SIZE
        fi
    fi

    sleep 20
    ELAPSED=$((ELAPSED + 20))

    # Check if PID is still running
    if [ -f /home/ga/virtualmin-install.pid ]; then
        INSTALL_PID=$(cat /home/ga/virtualmin-install.pid)
        if ! kill -0 "$INSTALL_PID" 2>/dev/null; then
            echo "  [${ELAPSED}s] Installer PID $INSTALL_PID has exited"
            # Even if PID is gone, virtualmin might now be available
            sleep 5
            if which virtualmin > /dev/null 2>&1; then
                echo "=== Virtualmin is now available ==="
                break
            fi
        fi
    fi
done

# Final check
if ! which virtualmin > /dev/null 2>&1; then
    echo "=== ERROR: Virtualmin not available after ${ELAPSED}s ==="
    echo "--- Install log tail ---"
    tail -50 /home/ga/virtualmin-install.log 2>/dev/null || true
    echo "--- End of install log ---"
    exit 1
fi

echo "--- Virtualmin is installed! ---"
sleep 5

# ---------------------------------------------------------------
# 2. Ensure critical services are running
# ---------------------------------------------------------------
# Fix Webmin referrer checking to allow direct URL navigation from address bar
# Must fix BOTH /etc/webmin/config AND /etc/webmin/miniserv.conf
sed -i 's/^referers_none=1/referers_none=0/' /etc/webmin/config 2>/dev/null || true
grep -q "^referers_none=" /etc/webmin/config 2>/dev/null || echo "referers_none=0" >> /etc/webmin/config
sed -i 's/^referers_none=1/referers_none=0/' /etc/webmin/miniserv.conf 2>/dev/null || true
grep -q "^referers_none=" /etc/webmin/miniserv.conf 2>/dev/null || echo "referers_none=0" >> /etc/webmin/miniserv.conf
echo "--- Webmin referer checking disabled (config + miniserv.conf) ---"
echo "--- Ensuring services are running ---"
for svc in apache2 mariadb named postfix dovecot webmin; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo "  $svc: running"
    else
        echo "  $svc: starting..."
        systemctl start "$svc" 2>&1 | tail -2 || echo "  WARNING: Could not start $svc"
    fi
done
sleep 5

# ---------------------------------------------------------------
# 3. Wait for Webmin to be reachable (HTTPS on port 10000)
# ---------------------------------------------------------------
echo "--- Waiting for Webmin HTTPS service ---"
WEB_TIMEOUT=180
WEB_ELAPSED=0
while [ $WEB_ELAPSED -lt $WEB_TIMEOUT ]; do
    if curl -sk https://localhost:10000/ > /dev/null 2>&1; then
        echo "Webmin is up (${WEB_ELAPSED}s)"
        break
    fi
    sleep 5
    WEB_ELAPSED=$((WEB_ELAPSED + 5))
    echo "  Still waiting for Webmin... (${WEB_ELAPSED}s)"
done

# ---------------------------------------------------------------
# 4. Configure MariaDB root password
# ---------------------------------------------------------------
echo "--- Configuring MariaDB root password ---"
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'GymAnything123!';" 2>/dev/null \
    || mysql -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('GymAnything123!');" 2>/dev/null \
    || mysqladmin -u root password 'GymAnything123!' 2>/dev/null \
    || echo "WARNING: Could not set MariaDB root password via standard methods"

# Try with existing password in case we've already set it
mysql -u root -pGymAnything123! -e "FLUSH PRIVILEGES;" 2>/dev/null || true

# Update Webmin MySQL module to know the root password
cat > /etc/webmin/mysql/config << 'EOF'
login=root
pass=GymAnything123!
host=localhost
port=3306
nodbi=0
date_subs=0
auto_quotas=0
EOF
echo "--- MariaDB configured ---"

# ---------------------------------------------------------------
# 5. Bypass Virtualmin post-install wizard
# ---------------------------------------------------------------
echo "--- Bypassing Virtualmin post-install wizard ---"

mkdir -p /etc/webmin/virtual-server

VSCONFIG=/etc/webmin/virtual-server/config

# Remove any duplicate keys we'll be setting
if [ -f "$VSCONFIG" ]; then
    for key in wizard_run mysql_pass mysql_user mysql_ssl mysql_hosts_default \
                pre_check avail_mysql avail_postgre avail_spam avail_virus \
                spam_server virus_server home_style plan_limits_default \
                default_db features_default avail_webalizer avail_logrotate \
                avail_ssl avail_dns avail_mail avail_web avail_ftp \
                avail_dir avail_webmin mail_system mysql_suffix; do
        grep -v "^${key}=" "$VSCONFIG" > /tmp/vs_config_tmp.txt 2>/dev/null || true
        mv /tmp/vs_config_tmp.txt "$VSCONFIG" 2>/dev/null || true
    done
fi

cat >> "$VSCONFIG" << 'EOF'
wizard_run=1
mysql_pass=GymAnything123!
mysql_user=root
mysql_ssl=0
mysql_hosts_default=1
pre_check=1
avail_mysql=1
avail_postgre=0
avail_spam=1
avail_virus=0
spam_server=0
virus_server=0
home_style=user
plan_limits_default=1
default_db=1
features_default=1
avail_webalizer=1
avail_logrotate=1
avail_ssl=1
avail_dns=1
avail_mail=1
avail_web=1
avail_ftp=1
avail_dir=1
avail_webmin=1
mail_system=0
mysql_suffix=_
EOF

echo "--- Wizard bypass config written ---"

# ---------------------------------------------------------------
# 6. Run Virtualmin configuration check
# ---------------------------------------------------------------
echo "--- Running virtualmin check-config ---"
virtualmin check-config 2>&1 | tail -30 || echo "WARNING: check-config returned non-zero"

# Wait for services to settle after check-config
echo "--- Waiting 20s for services to settle after check-config ---"
sleep 20

# ---------------------------------------------------------------
# 7. Create pre-seeded virtual servers
# ---------------------------------------------------------------
echo "--- Creating pre-seeded virtual servers ---"

create_vserver() {
    local domain="$1"
    local pass="$2"
    echo "Creating $domain..."
    virtualmin create-domain \
        --domain "$domain" \
        --pass "$pass" \
        --unix \
        --dir \
        --webmin \
        --web \
        --dns \
        --mail \
        --mysql 2>&1 | tail -5 \
        || echo "WARNING: Could not create $domain (may already exist)"
    sleep 5
}

# acmecorp.test — technology company
create_vserver "acmecorp.test" "AcmePwd789!"
# Note: --email flag does NOT exist in Virtualmin CLI; email is auto-derived as user@domain
virtualmin create-user --domain acmecorp.test --user admin \
    --pass "Admin123!" --real "Admin User" 2>&1 | tail -3 || true
virtualmin create-user --domain acmecorp.test --user info \
    --pass "Info123!" --real "Information Desk" 2>&1 | tail -3 || true
virtualmin create-user --domain acmecorp.test --user sales \
    --pass "Sales123!" --real "Sales Team" 2>&1 | tail -3 || true
virtualmin create-user --domain acmecorp.test --user support \
    --pass "Support123!" --real "Support Team" 2>&1 | tail -3 || true
virtualmin create-alias --domain acmecorp.test --from webmaster \
    --to admin@acmecorp.test 2>&1 | tail -3 || true

echo "--- acmecorp.test done ---"

# brightstar.test — media company
create_vserver "brightstar.test" "BrightPwd456!"
virtualmin create-user --domain brightstar.test --user admin \
    --pass "Admin123!" --real "Admin User" 2>&1 | tail -3 || true
virtualmin create-user --domain brightstar.test --user info \
    --pass "Info123!" --real "Information Desk" 2>&1 | tail -3 || true
virtualmin create-user --domain brightstar.test --user editor \
    --pass "Editor123!" --real "Content Editor" 2>&1 | tail -3 || true

echo "--- brightstar.test done ---"

# greenvalley.test — agricultural business
create_vserver "greenvalley.test" "GreenPwd123!"
virtualmin create-user --domain greenvalley.test --user admin \
    --pass "Admin123!" --real "Admin User" 2>&1 | tail -3 || true
virtualmin create-user --domain greenvalley.test --user orders \
    --pass "Orders123!" --real "Orders Team" 2>&1 | tail -3 || true

echo "--- greenvalley.test done ---"

# List all created domains
echo "--- Created domains ---"
virtualmin list-domains --name-only 2>&1 || true

# ---------------------------------------------------------------
# 8. Install real data into virtual servers
# ---------------------------------------------------------------
echo "--- Installing real data into virtual servers ---"

# 8a. Deploy Bootstrap 5 Album template to acmecorp.test public_html
#     Source: Bootstrap 5 official example template (public domain / MIT)
echo "--- Downloading Bootstrap Album template for acmecorp.test ---"
ALBUM_HTML=$(curl -fsSL \
    "https://raw.githubusercontent.com/twbs/bootstrap/main/site/content/docs/5.3/examples/album/index.html" \
    2>/dev/null || echo "")

if [ -n "$ALBUM_HTML" ] && [ ${#ALBUM_HTML} -gt 5000 ]; then
    echo "$ALBUM_HTML" > /home/acmecorp/public_html/index.html
    chown acmecorp:acmecorp /home/acmecorp/public_html/index.html
    chmod 644 /home/acmecorp/public_html/index.html
    echo "--- Bootstrap Album template deployed (${#ALBUM_HTML} bytes) ---"
else
    # Fallback: download from alternative URL
    curl -fsSL \
        "https://raw.githubusercontent.com/StartBootstrap/startbootstrap-freelancer/master/dist/index.html" \
        -o /home/acmecorp/public_html/index.html 2>/dev/null \
        && chown acmecorp:acmecorp /home/acmecorp/public_html/index.html \
        && echo "--- Bootstrap Freelancer template deployed (fallback) ---" \
        || echo "WARNING: Could not download Bootstrap template"
fi

# 8b. Import Sakila sample database
#     Sakila is the official MySQL sample database (open source, BSD-like license)
#     The schema creates a 'sakila' database — we import it standalone and link
#     virtual server users to it for a realistic data setup.
echo "--- Downloading Sakila sample database ---"
if curl -fsSL "https://downloads.mysql.com/docs/sakila-db.tar.gz" \
        -o /tmp/sakila-db.tar.gz 2>/dev/null && \
        [ -f /tmp/sakila-db.tar.gz ] && \
        [ "$(wc -c < /tmp/sakila-db.tar.gz)" -gt 100000 ]; then
    cd /tmp
    tar xzf sakila-db.tar.gz 2>/dev/null
    if [ -f /tmp/sakila-db/sakila-schema.sql ] && [ -f /tmp/sakila-db/sakila-data.sql ]; then
        # Import Sakila into its own 'sakila' database (schema file uses CREATE DATABASE sakila)
        echo "--- Importing Sakila schema (1000 films, 200 actors, 599 customers) ---"
        mysql -u root -pGymAnything123! < /tmp/sakila-db/sakila-schema.sql 2>/dev/null \
            && mysql -u root -pGymAnything123! < /tmp/sakila-db/sakila-data.sql 2>/dev/null \
            && echo "--- Sakila database imported successfully ---" \
            || echo "WARNING: Sakila import failed"
        # Grant acmecorp virtual server's MySQL user access to sakila
        mysql -u root -pGymAnything123! -e \
            "GRANT ALL ON sakila.* TO 'acmecorp'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null || true
    else
        echo "WARNING: Sakila SQL files not found after extraction"
    fi
else
    echo "WARNING: Could not download Sakila database"
fi

# 8c. Populate email Maildirs with real SpamAssassin corpus emails
#     Source: Apache SpamAssassin public email corpus (CC0/public domain)
echo "--- Downloading SpamAssassin email corpus ---"
SA_URL="https://spamassassin.apache.org/old/publiccorpus/20030228_easy_ham.tar.bz2"
if curl -fsSL "$SA_URL" -o /tmp/sa_ham.tar.bz2 2>/dev/null && \
        [ -f /tmp/sa_ham.tar.bz2 ] && \
        [ "$(wc -c < /tmp/sa_ham.tar.bz2)" -gt 500000 ]; then
    cd /tmp
    tar xjf sa_ham.tar.bz2 2>/dev/null
    HAM_DIR=/tmp/easy_ham

    if [ -d "$HAM_DIR" ]; then
        EMAIL_COUNT=$(ls "$HAM_DIR" | wc -l)
        echo "--- SpamAssassin corpus: $EMAIL_COUNT emails ---"

        # Populate acmecorp admin mailbox with real emails (first 25 emails)
        populate_maildir() {
            local maildir="$1"
            local count="$2"
            mkdir -p "${maildir}/new" "${maildir}/cur" "${maildir}/tmp"
            local n=0
            for f in "$HAM_DIR"/[0-9]*; do
                [ -f "$f" ] || continue
                [ $n -ge $count ] && break
                local fname="${f##*/}"
                # Rename to valid Maildir format: timestamp.pid.hostname
                local ts=$(($(date +%s) + n))
                cp "$f" "${maildir}/new/${ts}.${n}.virtualmin.gym-anything.local"
                n=$((n + 1))
            done
            echo "    Populated $n emails into $maildir"
        }

        # acmecorp.test mailboxes
        if [ -d /home/acmecorp/homes/admin/Maildir ]; then
            populate_maildir "/home/acmecorp/homes/admin/Maildir" 20
            chown -R acmecorp:acmecorp /home/acmecorp/homes/admin/Maildir
        fi
        if [ -d /home/acmecorp/homes/info/Maildir ]; then
            populate_maildir "/home/acmecorp/homes/info/Maildir" 10
            chown -R acmecorp:acmecorp /home/acmecorp/homes/info/Maildir
        fi

        # brightstar.test mailboxes
        if [ -d /home/brightstar/homes/admin/Maildir ]; then
            populate_maildir "/home/brightstar/homes/admin/Maildir" 15
            chown -R brightstar:brightstar /home/brightstar/homes/admin/Maildir
        fi

        echo "--- Email Maildirs populated ---"
    else
        echo "WARNING: SpamAssassin easy_ham directory not found"
    fi
else
    echo "WARNING: Could not download SpamAssassin corpus"
fi

echo "--- Real data installation complete ---"

# ---------------------------------------------------------------
# 9. Set up Firefox with SSL exception for Virtualmin
# ---------------------------------------------------------------
echo "--- Setting up Firefox ---"

# Wait for GNOME desktop
sleep 8

# Warm-up Firefox (snap) to create the default profile directory
# Firefox snap does NOT support -profile flag, so we warm-up first
su - ga -c "DISPLAY=:1 firefox --headless about:blank &" 2>/dev/null \
    || su - ga -c "DISPLAY=:1 firefox about:blank &" 2>/dev/null || true
sleep 12

# Kill warmup Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 3

# Find the Firefox profile directory (snap vs deb package)
SNAP_PROFILE=$(find /home/ga/snap/firefox/common/.mozilla/firefox/ \
    -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
DEB_PROFILE=$(find /home/ga/.mozilla/firefox/ \
    -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
PROFILE_DIR="${SNAP_PROFILE:-$DEB_PROFILE}"

echo "--- Firefox profile: ${PROFILE_DIR:-not found} ---"

if [ -n "$PROFILE_DIR" ]; then
    cat > "$PROFILE_DIR/user.js" << 'FFEOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.policy.dataSubmissionPolicyAccepted", true);
user_pref("datareporting.policy.dataSubmissionPolicyNotifiedTime", "1234567890123");
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.tabs.warnOnClose", false);
FFEOF
    chown ga:ga "$PROFILE_DIR/user.js"
    echo "--- Injected user.js preferences ---"
fi

# Launch Firefox to Virtualmin
su - ga -c "DISPLAY=:1 firefox https://localhost:10000 &"
sleep 12

# Dismiss SSL/TLS warning:
# Firefox shows "Warning: Potential Security Risk Ahead"
# Click "Advanced..." then "Accept the Risk and Continue"
# Coordinates verified via visual_grounding on 1920x1080 display:
#   "Advanced..." button:          actual (1318, 705)
#   "Accept the Risk and Continue": actual (1251, 1008)
DISPLAY=:1 xdotool mousemove 1318 705 click 1
sleep 3
DISPLAY=:1 xdotool mousemove 1251 1008 click 1
sleep 5

# Log in as root / GymAnything123!
# Coordinates verified via visual_grounding on 1920x1080 display:
#   Username field: actual (993, 384)  [VG: 662,256]
#   Password field: actual (993, 426)  [VG: 662,284] — use Tab to move to password
#   Sign In button: actual (993, 511)  [VG: 662,341]
DISPLAY=:1 xdotool mousemove 993 384 click 1
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
DISPLAY=:1 xdotool type --clearmodifiers --delay 30 "root"
DISPLAY=:1 xdotool key Tab
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers --delay 30 "GymAnything123!"
DISPLAY=:1 xdotool mousemove 993 511 click 1
sleep 8

echo "--- Firefox setup complete ---"
echo "=== Virtualmin post_start setup complete ==="
