#!/bin/bash
set -e

# Ensure a safe PATH (guards against /etc/environment corruption from pre_start)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

echo "=== Setting up OrientDB ==="

# Wait for desktop to be ready
sleep 5

# Start OrientDB service
echo "Starting OrientDB service..."
systemctl start orientdb

# Wait for OrientDB HTTP API to be ready (port 2480)
echo "Waiting for OrientDB to start (port 2480)..."
TIMEOUT=180
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "root:GymAnything123!" \
        "http://localhost:2480/listDatabases" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "OrientDB is ready (after ${ELAPSED}s)"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: OrientDB did not start within ${TIMEOUT}s"
    echo "=== OrientDB service status ==="
    systemctl status orientdb || true
    echo "=== OrientDB log ==="
    journalctl -u orientdb --no-pager -n 50 || true
    exit 1
fi

# Extra wait for full initialization (OrientDB needs time to load the DemoDB)
sleep 10

# Verify DemoDB is loaded and has sufficient data
# OrientDB 3.2.36 includes a built-in DemoDB, but we must verify it has Hotels and Profiles.
# If not, we run our seeder which provides real-world travel agency data.
echo "Verifying DemoDB is available and populated..."
DEMODB_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "root:GymAnything123!" \
    "http://localhost:2480/database/demodb" 2>/dev/null || echo "000")

NEEDS_SEED=false

if [ "$DEMODB_CODE" = "200" ]; then
    echo "DemoDB exists — checking data volume..."
    HOTEL_COUNT=$(curl -s -X POST -u "root:GymAnything123!" \
        -H "Content-Type: application/json" \
        -d '{"command":"SELECT COUNT(*) as cnt FROM Hotels"}' \
        "http://localhost:2480/command/demodb/sql" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
    PROFILE_COUNT=$(curl -s -X POST -u "root:GymAnything123!" \
        -H "Content-Type: application/json" \
        -d '{"command":"SELECT COUNT(*) as cnt FROM Profiles"}' \
        "http://localhost:2480/command/demodb/sql" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
    echo "DemoDB Hotels: ${HOTEL_COUNT} records, Profiles: ${PROFILE_COUNT} records"
    if [ "$HOTEL_COUNT" -lt 5 ] || [ "$PROFILE_COUNT" -lt 5 ]; then
        echo "DemoDB has insufficient data (Hotels=${HOTEL_COUNT}, Profiles=${PROFILE_COUNT}), running full seeder..."
        NEEDS_SEED=true
    else
        echo "DemoDB is populated (Hotels=${HOTEL_COUNT}, Profiles=${PROFILE_COUNT})"
    fi
else
    echo "DemoDB not found (HTTP ${DEMODB_CODE}), running seeder..."
    NEEDS_SEED=true
fi

if [ "$NEEDS_SEED" = "true" ]; then
    echo "Seeding DemoDB with real travel agency data..."
    python3 /workspace/scripts/seed_demodb.py 2>&1 | tee /home/ga/orientdb_seed.log
    echo "Seeding complete. Exit code: $?"
fi

# Verify the two profiles required by link_records task exist; insert if missing
echo "Ensuring link_records profiles exist..."
for PROFILE_EMAIL in "domi@nek.gov" "seari@ubu.edu"; do
    EXISTS=$(curl -s -X POST -u "root:GymAnything123!" \
        -H "Content-Type: application/json" \
        -d "{\"command\":\"SELECT @rid FROM Profiles WHERE Email='${PROFILE_EMAIL}'\"}" \
        "http://localhost:2480/command/demodb/sql" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('result',[])))" 2>/dev/null || echo "0")
    if [ "$EXISTS" = "0" ]; then
        echo "  Profile ${PROFILE_EMAIL} missing — inserting..."
        if [ "$PROFILE_EMAIL" = "domi@nek.gov" ]; then
            curl -s -X POST -u "root:GymAnything123!" -H "Content-Type: application/json" \
                -d '{"command":"INSERT INTO Profiles SET Email='"'"'domi@nek.gov'"'"', Name='"'"'Isaac'"'"', Surname='"'"'Black'"'"', Gender='"'"'Male'"'"', Birthday='"'"'1982-07-14'"'"', Nationality='"'"'American'"'"'"}' \
                "http://localhost:2480/command/demodb/sql" > /dev/null 2>&1 || true
        else
            curl -s -X POST -u "root:GymAnything123!" -H "Content-Type: application/json" \
                -d '{"command":"INSERT INTO Profiles SET Email='"'"'seari@ubu.edu'"'"', Name='"'"'Rosie'"'"', Surname='"'"'Thornton'"'"', Gender='"'"'Female'"'"', Birthday='"'"'1990-11-03'"'"', Nationality='"'"'British'"'"'"}' \
                "http://localhost:2480/command/demodb/sql" > /dev/null 2>&1 || true
        fi
        echo "  Inserted ${PROFILE_EMAIL}"
    else
        echo "  Profile ${PROFILE_EMAIL} found OK"
    fi
done

# --- Firefox setup ---
echo "Setting up Firefox profile..."
mkdir -p /home/ga/.mozilla/firefox/orientdb.profile

cat > /home/ga/.mozilla/firefox/orientdb.profile/user.js << 'EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.startup.page", 0);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.newtab.preload", false);
user_pref("extensions.update.enabled", false);
user_pref("app.update.enabled", false);
user_pref("dom.disable_open_during_load", false);
EOF

cat > /home/ga/.mozilla/firefox/profiles.ini << 'EOF'
[Profile0]
Name=default
IsRelative=1
Path=orientdb.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF

chown -R ga:ga /home/ga/.mozilla

# Launch Firefox to OrientDB Studio home page
echo "Launching Firefox to OrientDB Studio..."
sleep 2
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile 'http://localhost:2480/studio/index.html' &"
sleep 8

# Confirm Firefox is open
WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
echo "Open windows: $WINDOWS"

echo "=== OrientDB setup complete ==="
echo "OrientDB Studio: http://localhost:2480/studio/index.html"
echo "Server credentials: root / GymAnything123!"
echo "Database: demodb  |  DB user: admin / admin"
