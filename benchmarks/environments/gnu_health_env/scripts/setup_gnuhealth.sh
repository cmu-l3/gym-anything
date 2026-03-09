#!/bin/bash
set -e

echo "=== Setting up GNU Health HIS 5.0 ==="

# Wait for desktop to be ready
sleep 5

# Ensure PostgreSQL is running
systemctl start postgresql || true
sleep 5

# ---------------------------------------------------------------
# Database setup
# ---------------------------------------------------------------

# Check if demo database was downloaded during install
if [ -f /tmp/gnuhealth-50-demo.sql ] && [ ! -f /tmp/gnuhealth-no-demo ]; then
    echo "=== Restoring official GNU Health 5.0 demo database ==="

    # Drop and recreate the health50 database
    su - postgres -c "dropdb --if-exists health50"
    su - postgres -c "createdb -O gnuhealth health50"

    # Restore the demo database (run as gnuhealth user to use peer auth)
    echo "Restoring demo database (this may take a few minutes)..."
    sudo -u gnuhealth psql -d health50 -f /tmp/gnuhealth-50-demo.sql 2>&1 | tail -20

    echo "Demo database restored successfully"
    rm -f /tmp/gnuhealth-50-demo.sql

    # CRITICAL: The demo DB has bcrypt password hashes ($2b$12$...) but trytond 7.0.x
    # uses passlib scrypt format. We must rehash all user passwords to scrypt format.
    # Dollar signs in the hash require using a Python script with parameterized SQL.
    echo "Rehashing user passwords to scrypt format (required for trytond 7.0.x)..."
    cat > /tmp/update_passwords.py << 'PYEOF'
#!/usr/bin/env python3
"""
Update GNU Health demo database passwords from bcrypt to scrypt format.
The demo DB was created with an older trytond that used bcrypt hashes ($2b$12$...).
Trytond 7.0.x uses passlib with scrypt. If a bcrypt hash is encountered,
CRYPT_CONTEXT.verify_and_update raises ValueError, breaking login.

We rehash all user passwords to 'gnusolidario' using the current CRYPT_CONTEXT.
"""
import sys
sys.path.insert(0, '/opt/gnuhealth/venv/lib/python3/site-packages')
# Find the actual python3 version directory
import glob
site_packages = glob.glob('/opt/gnuhealth/venv/lib/python3.*/site-packages')
if site_packages:
    sys.path.insert(0, site_packages[0])

try:
    from passlib.context import CryptContext
    # Match the context trytond uses
    CRYPT_CONTEXT = CryptContext(schemes=['scrypt'], deprecated='auto')
except ImportError:
    # Fallback: try importing from trytond directly
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "user",
        "/opt/gnuhealth/venv/lib/python3.*/site-packages/trytond/res/user.py"
    )

import psycopg2

# Generate scrypt hash for the demo password
new_hash = CRYPT_CONTEXT.hash('gnusolidario')
print(f"Generated scrypt hash: {new_hash[:30]}...")

# Update all user password hashes
conn = psycopg2.connect(dbname='health50', user='gnuhealth')
cur = conn.cursor()
cur.execute("SELECT COUNT(*) FROM res_user WHERE password_hash IS NOT NULL")
count = cur.fetchone()[0]
print(f"Updating {count} user password hashes...")
cur.execute(
    "UPDATE res_user SET password_hash = %s WHERE password_hash IS NOT NULL",
    (new_hash,)
)
conn.commit()
cur.close()
conn.close()
print("Password hashes updated successfully")
PYEOF

    sudo -u gnuhealth /opt/gnuhealth/venv/bin/python3 /tmp/update_passwords.py
    echo "Password rehashing complete"

    # Add HbA1c lab test type (Glycated Hemoglobin - essential for diabetes monitoring)
    echo "Adding HbA1c lab test type..."
    sudo -u gnuhealth psql -d health50 -c "
        INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
        SELECT
            (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
            'GLYCATED HEMOGLOBIN (HbA1c)',
            'HBA1C',
            true,
            1,
            NOW(),
            1,
            NOW()
        WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'HBA1C');
        INSERT INTO gnuhealth_lab_test_critearea (name, code, test_type_id, create_uid, create_date, write_uid, write_date)
        SELECT
            'HbA1c',
            'HBA1C',
            (SELECT id FROM gnuhealth_lab_test_type WHERE code = 'HBA1C'),
            1,
            NOW(),
            1,
            NOW()
        WHERE NOT EXISTS (
            SELECT 1 FROM gnuhealth_lab_test_critearea WHERE code = 'HBA1C'
        );
    " 2>/dev/null || true
    echo "HbA1c test type added"

    # Remove test/fake patients that were added during development (not part of official demo)
    # These are: 'dodo' (party 44) and 'Trịnh Trung Kiên 1993' (party 45)
    echo "Removing test patients from database..."
    sudo -u gnuhealth psql -d health50 -c "
        DELETE FROM gnuhealth_patient WHERE party IN (
            SELECT id FROM party_party WHERE name IN ('dodo') OR (name = 'Trịnh Trung Kiên 1993' AND lastname IS NULL)
        );
        DELETE FROM party_party WHERE name IN ('dodo') OR name = 'Trịnh Trung Kiên 1993';
    " 2>/dev/null || true
    echo "Test patients removed"

else
    echo "=== Initializing fresh GNU Health database ==="

    # Drop and recreate
    su - postgres -c "dropdb --if-exists health50"
    su - postgres -c "createdb -O gnuhealth health50"

    # Initialize the database with GNU Health modules
    ADMIN_PASS_FILE=$(mktemp)
    echo "gnusolidario" > "$ADMIN_PASS_FILE"

    sudo -u gnuhealth bash -c "
        source /opt/gnuhealth/venv/bin/activate
        TRYTONPASSFILE=$ADMIN_PASS_FILE trytond-admin \
            -c /opt/gnuhealth/trytond.conf \
            -d health50 \
            --all \
            --email admin@gnuhealth.local
    " 2>&1 | tail -50

    rm -f "$ADMIN_PASS_FILE"
    echo "Database initialized"
fi

# ---------------------------------------------------------------
# Update trytond.conf to point at health50 database
# (overwrite cleanly to avoid sed duplication issues)
# ---------------------------------------------------------------
cat > /opt/gnuhealth/trytond.conf << 'EOF'
[database]
uri = postgresql://gnuhealth@/health50

[web]
listen = 0.0.0.0:8000
root = /opt/gnuhealth/sao

[session]
timeout = 43200

[cache]
clean_timeout = 0

EOF
chown gnuhealth:gnuhealth /opt/gnuhealth/trytond.conf

# ---------------------------------------------------------------
# Create/reload systemd service and start GNU Health
# ---------------------------------------------------------------
# Create (or re-create) the gnuhealth systemd service
cat > /etc/systemd/system/gnuhealth.service << 'EOF'
[Unit]
Description=GNU Health Hospital Information System
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=gnuhealth
WorkingDirectory=/opt/gnuhealth
Environment=PATH=/opt/gnuhealth/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/gnuhealth/venv/bin/trytond -c /opt/gnuhealth/trytond.conf
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=gnuhealth

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gnuhealth

echo "Starting GNU Health HIS server..."
systemctl start gnuhealth

# Wait for the server to be ready (polls port 8000)
echo "Waiting for GNU Health server to be ready..."
TIMEOUT=180
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if curl -s --max-time 5 "http://localhost:8000/" > /dev/null 2>&1; then
        echo "GNU Health server is ready!"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
    if [ $((ELAPSED % 15)) -eq 0 ]; then
        echo "  Still waiting... ${ELAPSED}s"
    fi
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "WARNING: Server did not respond within ${TIMEOUT}s. Checking status..."
    systemctl status gnuhealth || true
    journalctl -u gnuhealth -n 30 || true
fi

# ---------------------------------------------------------------
# Configure Firefox
# ---------------------------------------------------------------
echo "Configuring Firefox..."

# Warm-up Firefox to create profile directory
su - ga -c "DISPLAY=:1 firefox --headless http://localhost:8000/ &" 2>/dev/null || true
sleep 10
pkill -f firefox || true
sleep 3

# Find the Firefox profile directory
FF_PROFILE_DIR=$(find /home/ga/.mozilla/firefox -name "*.default*" -maxdepth 1 -type d 2>/dev/null | head -1)

if [ -z "$FF_PROFILE_DIR" ]; then
    # Try any profile directory
    FF_PROFILE_DIR=$(find /home/ga/.mozilla/firefox -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -v profiles.ini | head -1)
fi

if [ -z "$FF_PROFILE_DIR" ]; then
    # Create a default profile
    FF_PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
    mkdir -p "$FF_PROFILE_DIR"
    cat > /home/ga/.mozilla/firefox/profiles.ini << 'PROFEOF'
[General]
StartWithLastProfile=1

[Profile0]
Name=default
IsRelative=1
Path=default.profile
Default=1
PROFEOF
fi

# Configure Firefox user preferences
cat > "${FF_PROFILE_DIR}/user.js" << 'USERJS'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("security.enterprise_roots.enabled", true);
user_pref("browser.startup.page", 1);
user_pref("browser.startup.homepage", "http://localhost:8000/");
user_pref("signon.rememberSignons", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("network.cookie.lifetimePolicy", 0);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.download.manager.showWhenStarting", false);
user_pref("browser.privatebrowsing.autostart", false);
USERJS

chown -R ga:ga /home/ga/.mozilla

# Create a convenient query helper script
cat > /usr/local/bin/gnuhealth-db-query << 'QUERYEOF'
#!/bin/bash
# Query the GNU Health PostgreSQL database
# Usage: gnuhealth-db-query "SELECT * FROM party_party LIMIT 5"
sudo -u gnuhealth psql -d health50 -N -c "$1" 2>/dev/null
QUERYEOF
chmod +x /usr/local/bin/gnuhealth-db-query

# ---------------------------------------------------------------
# Launch Firefox and navigate to GNU Health
# ---------------------------------------------------------------
echo "Launching Firefox with GNU Health..."
su - ga -c "DISPLAY=:1 firefox http://localhost:8000/ &"
sleep 12

# Maximize Firefox window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take screenshot to verify state
DISPLAY=:1 scrot /tmp/gnuhealth_setup.png 2>/dev/null || true

echo "=== GNU Health HIS setup complete ==="
echo "Access URL: http://localhost:8000/"
echo "Database: health50"
echo "Admin credentials: admin / gnusolidario"
echo "Demo users: cmegolsa, demo_frontdesk, demo_doctor (all password: gnusolidario)"
