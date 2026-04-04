#!/bin/bash
set -e

echo "=== Setting up OpenClinica ==="

# Wait for desktop to be ready
sleep 5

# OpenClinica URL
OC_URL="http://localhost:8080/OpenClinica"
OC_LOGIN_URL="${OC_URL}/MainMenu"

# ============================================================
# 1. Set up Docker Compose working directory
# ============================================================
echo "Setting up Docker Compose..."
OC_DIR="/home/ga/openclinica"
mkdir -p "$OC_DIR"
cp /workspace/config/docker-compose.yml "$OC_DIR/"
cp /workspace/config/init-db.sh "$OC_DIR/"
chmod 755 "$OC_DIR/init-db.sh"
chown -R ga:ga "$OC_DIR"

# ============================================================
# 2. Start Docker services
# ============================================================
echo "Starting OpenClinica services..."
cd "$OC_DIR"
docker-compose pull 2>&1 || echo "WARNING: Pull failed, using cached images"
docker-compose up -d

# ============================================================
# 3. Wait for PostgreSQL to be ready
# ============================================================
echo "Waiting for PostgreSQL..."
wait_for_postgres() {
    local timeout=${1:-120}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker exec oc-postgres pg_isready -U postgres 2>/dev/null; then
            echo "PostgreSQL is ready after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting for PostgreSQL... ${elapsed}s"
    done
    echo "WARNING: PostgreSQL wait timed out after ${timeout}s"
    return 1
}
wait_for_postgres 120 || true

# ============================================================
# 3.5 Ensure database role and database exist
# ============================================================
echo "Ensuring database role 'clinica' exists..."
ROLE_EXISTS=$(docker exec oc-postgres psql -U postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='clinica'" 2>/dev/null || echo "")
if [ "$ROLE_EXISTS" != "1" ]; then
    echo "Creating 'clinica' role..."
    docker exec oc-postgres psql -U postgres -c "CREATE ROLE clinica LOGIN ENCRYPTED PASSWORD 'clinica' SUPERUSER NOINHERIT NOCREATEDB NOCREATEROLE;" 2>/dev/null || echo "WARNING: Could not create clinica role"
else
    echo "Role 'clinica' already exists"
fi

DB_EXISTS=$(docker exec oc-postgres psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='openclinica'" 2>/dev/null || echo "")
if [ "$DB_EXISTS" != "1" ]; then
    echo "Creating 'openclinica' database..."
    docker exec oc-postgres psql -U postgres -c "CREATE DATABASE openclinica WITH ENCODING='UTF8' OWNER=clinica;" 2>/dev/null || echo "WARNING: Could not create openclinica database"
else
    echo "Database 'openclinica' already exists"
fi

# Restart OpenClinica container to pick up database changes
echo "Restarting OpenClinica container to connect to database..."
docker restart oc-app 2>/dev/null || true
sleep 10

# ============================================================
# 4. Wait for OpenClinica to be ready
# ============================================================
echo "Waiting for OpenClinica application..."
wait_for_openclinica() {
    local timeout=${1:-300}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${OC_URL}/" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "OpenClinica is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo "  Waiting for OpenClinica... ${elapsed}s (HTTP $HTTP_CODE)"
    done
    echo "WARNING: OpenClinica wait timed out after ${timeout}s"
    # Show container logs for debugging
    echo "=== OpenClinica container logs (last 50 lines) ==="
    docker logs oc-app --tail 50 2>&1 || true
    echo "=== End container logs ==="
    return 1
}
if ! wait_for_openclinica 300; then
    echo "ERROR: OpenClinica failed to start within 300s. Attempting recovery..."
    docker restart oc-app 2>/dev/null || true
    sleep 30
    if ! wait_for_openclinica 180; then
        echo "FATAL: OpenClinica still not ready after restart. Setup may be incomplete."
    fi
fi

# Additional wait for Tomcat full initialization
echo "Waiting additional 30s for full Tomcat initialization..."
sleep 30

# ============================================================
# 5. Handle first-run password change via database
# ============================================================
echo "Changing root password via database..."

# OpenClinica uses SHA-1 for password hashing
# SHA-1 of 'Admin123!' = 664819d8c5343676c9225b5ed00a5cdc6f3a1ff3
NEW_PASS_HASH="664819d8c5343676c9225b5ed00a5cdc6f3a1ff3"

# Set passwd_timestamp far in the future to prevent password reset page from appearing
docker exec oc-postgres psql -U clinica openclinica -c "
    UPDATE user_account SET
        passwd = '${NEW_PASS_HASH}',
        passwd_timestamp = CURRENT_DATE + INTERVAL '365 days',
        passwd_challenge_question = 'Favorite Animal',
        passwd_challenge_answer = 'blue'
    WHERE user_name = 'root';
" 2>/dev/null || echo "WARNING: Password update may have failed"

# Also mark the account as NOT requiring password change
# OpenClinica checks passwd_timestamp against a configured expiry period
# and also has a `user_account.enabled` flag. Ensure account_non_locked=true
docker exec oc-postgres psql -U clinica openclinica -c "
    UPDATE user_account SET
        account_non_locked = true
    WHERE user_name = 'root';
" 2>/dev/null || true

# Verify the update
VERIFY_HASH=$(docker exec oc-postgres psql -U clinica openclinica -tAc \
    "SELECT passwd FROM user_account WHERE user_name='root'" 2>/dev/null || echo "")
if [ "$VERIFY_HASH" = "$NEW_PASS_HASH" ]; then
    echo "Root password successfully changed to Admin123!"
else
    echo "WARNING: Password hash mismatch. Expected: $NEW_PASS_HASH Got: $VERIFY_HASH"
fi

# Restart Tomcat to clear any cached session state that thinks password needs reset
echo "Restarting OpenClinica to clear cached session state..."
docker restart oc-app 2>/dev/null || true
sleep 10

# Wait for OpenClinica to come back up after restart
echo "Waiting for OpenClinica to restart..."
if ! wait_for_openclinica 180; then
    echo "WARNING: OpenClinica slow to restart after password change"
fi
sleep 10

# ============================================================
# 6. Create baseline study via database
# ============================================================
echo "Creating baseline study data..."

# Wait a bit for any pending database operations
sleep 5

# Create a baseline study so tasks have context
docker exec oc-postgres psql -U clinica openclinica -c "
    INSERT INTO study (
        name, unique_identifier, status_id, owner_id,
        date_created, protocol_type, principal_investigator,
        summary, date_planned_start, protocol_date_verification, oc_oid
    )
    SELECT
        'Phase II Diabetes Trial',
        'DM-TRIAL-2024',
        1,
        1,
        CURRENT_DATE,
        'interventional',
        'Dr. Sarah Chen',
        'A Phase II, randomized, double-blind, placebo-controlled trial to evaluate the efficacy and safety of investigational treatment in patients with Type 2 Diabetes Mellitus.',
        CURRENT_DATE,
        CURRENT_DATE,
        'S_DM2024'
    WHERE NOT EXISTS (
        SELECT 1 FROM study WHERE unique_identifier = 'DM-TRIAL-2024'
    );
" 2>/dev/null || echo "Note: Baseline study creation may have failed (table schema may differ)"

echo "Baseline study setup attempted"

# ============================================================
# 6b. Pre-populate database with realistic complexity
# ============================================================
echo "Pre-populating database with realistic data..."

# Add a second study (observational) so the studies list is not trivially empty
docker exec oc-postgres psql -U clinica openclinica -c "
    INSERT INTO study (
        name, unique_identifier, status_id, owner_id,
        date_created, protocol_type, principal_investigator,
        summary, date_planned_start, protocol_date_verification, oc_oid
    )
    SELECT
        'Cardiovascular Outcomes Registry',
        'CV-REG-2023',
        1,
        1,
        CURRENT_DATE - INTERVAL '180 days',
        'observational',
        'Dr. Michael Rivera',
        'A prospective observational registry tracking cardiovascular outcomes and risk factors in patients with established coronary artery disease across multiple clinical sites.',
        CURRENT_DATE - INTERVAL '180 days',
        CURRENT_DATE - INTERVAL '180 days',
        'S_CVREG23'
    WHERE NOT EXISTS (
        SELECT 1 FROM study WHERE unique_identifier = 'CV-REG-2023'
    );
" 2>/dev/null || true

# Add a third study (completed/locked) for navigation complexity
docker exec oc-postgres psql -U clinica openclinica -c "
    INSERT INTO study (
        name, unique_identifier, status_id, owner_id,
        date_created, protocol_type, principal_investigator,
        summary, date_planned_start, protocol_date_verification, oc_oid
    )
    SELECT
        'Asthma Prevention Pilot',
        'AP-PILOT-2022',
        4,
        1,
        CURRENT_DATE - INTERVAL '365 days',
        'interventional',
        'Dr. Emily Rodriguez',
        'A pilot feasibility study assessing early intervention strategies for asthma prevention in pediatric populations with familial predisposition.',
        CURRENT_DATE - INTERVAL '365 days',
        CURRENT_DATE - INTERVAL '365 days',
        'S_APPLT22'
    WHERE NOT EXISTS (
        SELECT 1 FROM study WHERE unique_identifier = 'AP-PILOT-2022'
    );
" 2>/dev/null || true

# Add pre-existing user accounts (data manager and monitor) so user list is populated
docker exec oc-postgres psql -U clinica openclinica -c "
    INSERT INTO user_account (
        user_name, passwd, first_name, last_name, email,
        status_id, owner_id, date_created,
        institutional_affiliation, passwd_timestamp, passwd_challenge_question,
        passwd_challenge_answer, phone, account_non_locked,
        lock_counter, enabled
    )
    SELECT
        'mrivera',
        '5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8',
        'Michael',
        'Rivera',
        'mrivera@cardiohealth.org',
        1,
        1,
        CURRENT_DATE - INTERVAL '90 days',
        'CardioHealth Research Center',
        CURRENT_DATE + INTERVAL '365 days',
        'What is your favorite color?',
        '5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8',
        '555-0102',
        true,
        0,
        true
    WHERE NOT EXISTS (
        SELECT 1 FROM user_account WHERE user_name = 'mrivera'
    );
" 2>/dev/null || true

docker exec oc-postgres psql -U clinica openclinica -c "
    INSERT INTO user_account (
        user_name, passwd, first_name, last_name, email,
        status_id, owner_id, date_created,
        institutional_affiliation, passwd_timestamp, passwd_challenge_question,
        passwd_challenge_answer, phone, account_non_locked,
        lock_counter, enabled
    )
    SELECT
        'lchang',
        '5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8',
        'Lisa',
        'Chang',
        'lchang@clinicalmonitors.com',
        1,
        1,
        CURRENT_DATE - INTERVAL '60 days',
        'Clinical Monitors Inc.',
        CURRENT_DATE + INTERVAL '365 days',
        'What is your favorite color?',
        '5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8',
        '555-0203',
        true,
        0,
        true
    WHERE NOT EXISTS (
        SELECT 1 FROM user_account WHERE user_name = 'lchang'
    );
" 2>/dev/null || true

# Assign roles to pre-existing users
# Get study IDs
DM_STUDY_ID=$(docker exec oc-postgres psql -U clinica openclinica -t -A -c "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1" 2>/dev/null)
CV_STUDY_ID=$(docker exec oc-postgres psql -U clinica openclinica -t -A -c "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' LIMIT 1" 2>/dev/null)
DEFAULT_STUDY_ID=1

if [ -n "$DM_STUDY_ID" ]; then
    # mrivera as data manager on the DM trial
    docker exec oc-postgres psql -U clinica openclinica -c "
        INSERT INTO study_user_role (role_name, study_id, status_id, owner_id, date_created, date_updated, update_id, user_name)
        SELECT 'data_manager', $DM_STUDY_ID, 1, 1, CURRENT_DATE - INTERVAL '90 days', CURRENT_DATE, 1, 'mrivera'
        WHERE NOT EXISTS (
            SELECT 1 FROM study_user_role WHERE user_name = 'mrivera' AND study_id = $DM_STUDY_ID
        );
    " 2>/dev/null || true
fi

if [ -n "$CV_STUDY_ID" ]; then
    # lchang as monitor on the CV registry
    docker exec oc-postgres psql -U clinica openclinica -c "
        INSERT INTO study_user_role (role_name, study_id, status_id, owner_id, date_created, date_updated, update_id, user_name)
        SELECT 'monitor', $CV_STUDY_ID, 1, 1, CURRENT_DATE - INTERVAL '60 days', CURRENT_DATE, 1, 'lchang'
        WHERE NOT EXISTS (
            SELECT 1 FROM study_user_role WHERE user_name = 'lchang' AND study_id = $CV_STUDY_ID
        );
    " 2>/dev/null || true
fi

# Add pre-existing study event definitions to the CV registry
if [ -n "$CV_STUDY_ID" ]; then
    docker exec oc-postgres psql -U clinica openclinica -c "
        INSERT INTO study_event_definition (
            study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal
        )
        SELECT
            $CV_STUDY_ID, 'Baseline Assessment', 'Initial cardiovascular baseline assessment and risk factor documentation', false, 'scheduled', 1, 1, CURRENT_DATE - INTERVAL '90 days', 'SE_CVBASE', 1
        WHERE NOT EXISTS (
            SELECT 1 FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = $CV_STUDY_ID
        );
    " 2>/dev/null || true

    docker exec oc-postgres psql -U clinica openclinica -c "
        INSERT INTO study_event_definition (
            study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal
        )
        SELECT
            $CV_STUDY_ID, 'Follow-up Visit', 'Quarterly follow-up assessment for cardiovascular outcomes tracking', true, 'scheduled', 1, 1, CURRENT_DATE - INTERVAL '60 days', 'SE_CVFUP', 2
        WHERE NOT EXISTS (
            SELECT 1 FROM study_event_definition WHERE name = 'Follow-up Visit' AND study_id = $CV_STUDY_ID
        );
    " 2>/dev/null || true
fi

# Add pre-existing subjects to the DM trial (so subject list is not empty)
if [ -n "$DM_STUDY_ID" ]; then
    # Create subject records first
    docker exec oc-postgres psql -U clinica openclinica -c "
        INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created, unique_identifier, dob_collected)
        SELECT '1968-03-22', 'f', 1, 1, CURRENT_DATE - INTERVAL '30 days', 'SUBJ_DM_01', true
        WHERE NOT EXISTS (
            SELECT 1 FROM subject WHERE unique_identifier = 'SUBJ_DM_01'
        );
    " 2>/dev/null || true

    docker exec oc-postgres psql -U clinica openclinica -c "
        INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created, unique_identifier, dob_collected)
        SELECT '1952-11-07', 'm', 1, 1, CURRENT_DATE - INTERVAL '25 days', 'SUBJ_DM_02', true
        WHERE NOT EXISTS (
            SELECT 1 FROM subject WHERE unique_identifier = 'SUBJ_DM_02'
        );
    " 2>/dev/null || true

    docker exec oc-postgres psql -U clinica openclinica -c "
        INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created, unique_identifier, dob_collected)
        SELECT '1980-07-14', 'f', 1, 1, CURRENT_DATE - INTERVAL '20 days', 'SUBJ_DM_03', true
        WHERE NOT EXISTS (
            SELECT 1 FROM subject WHERE unique_identifier = 'SUBJ_DM_03'
        );
    " 2>/dev/null || true

    # Link subjects to the DM study as study_subjects
    SUBJ1_ID=$(docker exec oc-postgres psql -U clinica openclinica -t -A -c "SELECT subject_id FROM subject WHERE unique_identifier = 'SUBJ_DM_01' LIMIT 1" 2>/dev/null)
    SUBJ2_ID=$(docker exec oc-postgres psql -U clinica openclinica -t -A -c "SELECT subject_id FROM subject WHERE unique_identifier = 'SUBJ_DM_02' LIMIT 1" 2>/dev/null)
    SUBJ3_ID=$(docker exec oc-postgres psql -U clinica openclinica -t -A -c "SELECT subject_id FROM subject WHERE unique_identifier = 'SUBJ_DM_03' LIMIT 1" 2>/dev/null)

    if [ -n "$SUBJ1_ID" ]; then
        docker exec oc-postgres psql -U clinica openclinica -c "
            INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created, enrollment_date, oc_oid)
            SELECT 'DM-101', $SUBJ1_ID, $DM_STUDY_ID, 1, 1, CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE - INTERVAL '30 days', 'SS_DM101'
            WHERE NOT EXISTS (SELECT 1 FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID);
        " 2>/dev/null || true
    fi

    if [ -n "$SUBJ2_ID" ]; then
        docker exec oc-postgres psql -U clinica openclinica -c "
            INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created, enrollment_date, oc_oid)
            SELECT 'DM-102', $SUBJ2_ID, $DM_STUDY_ID, 1, 1, CURRENT_DATE - INTERVAL '25 days', CURRENT_DATE - INTERVAL '25 days', 'SS_DM102'
            WHERE NOT EXISTS (SELECT 1 FROM study_subject WHERE label = 'DM-102' AND study_id = $DM_STUDY_ID);
        " 2>/dev/null || true
    fi

    if [ -n "$SUBJ3_ID" ]; then
        docker exec oc-postgres psql -U clinica openclinica -c "
            INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created, enrollment_date, oc_oid)
            SELECT 'DM-103', $SUBJ3_ID, $DM_STUDY_ID, 1, 1, CURRENT_DATE - INTERVAL '20 days', CURRENT_DATE - INTERVAL '20 days', 'SS_DM103'
            WHERE NOT EXISTS (SELECT 1 FROM study_subject WHERE label = 'DM-103' AND study_id = $DM_STUDY_ID);
        " 2>/dev/null || true
    fi
fi

echo "Database pre-population complete"

# ============================================================
# 7. Database query utility (internal use only, not exposed to agent)
# ============================================================
# Note: oc-db-query is NOT created as a user-accessible tool.
# Database queries are only used internally by export_result.sh scripts
# via task_utils.sh oc_query() function. This prevents agents from
# bypassing the GUI by directly inserting records via SQL.
echo "Skipping oc-db-query creation (agents must use GUI)"

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

// Set homepage to OpenClinica
user_pref("browser.startup.homepage", "http://localhost:8080/OpenClinica/MainMenu");
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
cat > /home/ga/Desktop/OpenClinica.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=OpenClinica
Comment=OpenClinica Clinical Trial Management
Exec=firefox http://localhost:8080/OpenClinica/MainMenu
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/OpenClinica.desktop
chmod +x /home/ga/Desktop/OpenClinica.desktop

# ============================================================
# 9. Verify OpenClinica login works before launching Firefox
# ============================================================
echo "Verifying login works via curl..."
LOGIN_OK=false
for attempt in 1 2 3; do
    # Try to log in via curl to verify credentials work
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -d "j_username=root&j_password=Admin123!" \
        -L "${OC_URL}/j_spring_security_check" 2>/dev/null || echo "000")
    echo "  Login attempt $attempt: HTTP $HTTP_CODE"
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        LOGIN_OK=true
        break
    fi
    sleep 5
done

if [ "$LOGIN_OK" = false ]; then
    echo "WARNING: Could not verify login via curl. Password may need manual reset."
    echo "  Checking if password reset page would appear..."
    PASSWD_TS=$(docker exec oc-postgres psql -U clinica openclinica -tAc \
        "SELECT passwd_timestamp FROM user_account WHERE user_name='root'" 2>/dev/null || echo "")
    echo "  passwd_timestamp = $PASSWD_TS"
fi

# ============================================================
# 10. Launch Firefox
# ============================================================
echo "Launching Firefox with OpenClinica..."
su - ga -c "DISPLAY=:1 firefox '${OC_LOGIN_URL}' > /tmp/firefox_openclinica.log 2>&1 &"

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

    # Wait for OpenClinica page to load
    echo "Waiting for OpenClinica page to load in Firefox..."
    PAGE_LOADED=false
    for i in {1..60}; do
        WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
        if echo "$WINDOW_TITLE" | grep -qi "openclinica\|clinical"; then
            PAGE_LOADED=true
            echo "OpenClinica page detected in window title after ${i}s"
            break
        fi
        sleep 1
    done

    if [ "$PAGE_LOADED" = false ]; then
        echo "WARNING: OpenClinica page title not detected after 60s"
        echo "Current window title: $(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i firefox)"
        echo "Attempting to refresh..."
        DISPLAY=:1 xdotool key F5 2>/dev/null || true
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
echo "=== OpenClinica Setup Complete ==="
echo ""
echo "OpenClinica is running at: ${OC_URL}"
echo "Login page: ${OC_LOGIN_URL}"
echo ""
echo "Login Credentials:"
echo "  Admin: root / Admin123!"
echo ""
echo "Docker containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
echo ""
