#!/bin/bash
# Sakai LMS Setup Script (post_start hook)
# Starts MariaDB (Docker), deploys sakai.properties, starts Tomcat,
# seeds demo data (courses, enrollments), and launches Firefox
#
# Default credentials:
#   Admin: admin / admin
#   Instructor: instructor / sakai
#   Students: student0001-student0500 / sakai

echo "=== Setting up Sakai LMS ==="

# Source environment variables
source /etc/profile.d/java.sh 2>/dev/null || true
source /etc/profile.d/maven.sh 2>/dev/null || true
source /etc/profile.d/tomcat.sh 2>/dev/null || true

export CATALINA_HOME="${CATALINA_HOME:-/opt/tomcat}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"

SAKAI_URL="http://localhost:8080/portal"
ADMIN_USER="admin"
ADMIN_PASS="admin"

# Wait for desktop to be ready
sleep 5

# ============================================================
# 1. Start MariaDB via Docker
# ============================================================
echo "--- Starting MariaDB ---"
mkdir -p /home/ga/sakai
cp /workspace/config/docker-compose.yml /home/ga/sakai/
chown -R ga:ga /home/ga/sakai

# Authenticate with Docker Hub
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
fi

cd /home/ga/sakai
docker compose pull 2>&1 || echo "WARNING: Docker pull may have failed, trying with cached images"
docker compose up -d

# Wait for MariaDB to be ready
wait_for_mariadb() {
    local timeout=${1:-120}
    local elapsed=0
    echo "Waiting for MariaDB..."
    while [ $elapsed -lt $timeout ]; do
        if docker exec sakai-db mysqladmin ping -h localhost -u root -prootpass 2>/dev/null | grep -q "alive"; then
            echo "MariaDB is ready after ${elapsed}s"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
        if [ $((elapsed % 15)) -eq 0 ]; then
            echo "  Waiting for MariaDB... ${elapsed}s"
        fi
    done
    echo "ERROR: MariaDB not ready after ${timeout}s"
    return 1
}

wait_for_mariadb 120

# Verify database
docker exec sakai-db mysql -u root -prootpass -e "SHOW DATABASES;" 2>/dev/null
echo "MariaDB container status:"
docker compose ps

# ============================================================
# 2. Deploy Sakai configuration
# ============================================================
echo "--- Deploying sakai.properties ---"
cp /workspace/config/sakai.properties /opt/sakai/sakai.properties
chown ga:ga /opt/sakai/sakai.properties

# ============================================================
# 3. Start Tomcat (Sakai)
# ============================================================
echo "--- Starting Sakai (Tomcat) ---"
echo "First boot creates database schema — this takes 3-10 minutes..."

# Start Tomcat as user ga
su - ga -c "export JAVA_HOME=$JAVA_HOME && export CATALINA_HOME=$CATALINA_HOME && $CATALINA_HOME/bin/startup.sh" 2>&1

# ============================================================
# 4. Wait for Sakai to be fully ready
# ============================================================
wait_for_sakai() {
    local timeout=${1:-600}
    local elapsed=0
    echo "Waiting for Sakai web interface..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SAKAI_URL" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            echo "Sakai is ready (HTTP $HTTP_CODE) after ${elapsed}s"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        if [ $((elapsed % 60)) -eq 0 ]; then
            echo "  Still waiting for Sakai... ${elapsed}s (HTTP: $HTTP_CODE)"
            # Show last few lines of Tomcat log for diagnostics
            tail -3 "$CATALINA_HOME/logs/catalina.out" 2>/dev/null || true
        fi
    done
    echo "ERROR: Sakai not ready after ${timeout}s"
    return 1
}

wait_for_sakai 600

# Extra wait for full initialization after first response
sleep 15

# Verify Sakai is running
echo "Verifying Sakai endpoints..."
curl -s -o /dev/null -w "Portal: HTTP %{http_code}\n" "$SAKAI_URL" 2>/dev/null
curl -s -o /dev/null -w "Login: HTTP %{http_code}\n" "http://localhost:8080/portal/login" 2>/dev/null

# ============================================================
# 5. Seed demo data via direct SQL (REST API is unreliable in Sakai 25)
# ============================================================
echo "--- Seeding demo data via SQL ---"

docker exec -i sakai-db mysql -u sakai -psakaipass sakai << 'EOSQL'
-- Create course sites
INSERT IGNORE INTO SAKAI_SITE (SITE_ID, TITLE, TYPE, SHORT_DESC, DESCRIPTION, ICON_URL, SKIN, PUBLISHED, JOINABLE, PUBVIEW, JOIN_ROLE, IS_SOFTLY_DELETED, SOFTLY_DELETED_DATE, CREATEDBY, MODIFIEDBY, CREATEDON, MODIFIEDON, CUSTOM_PAGE_ORDERED, IS_SPECIAL, IS_USER)
VALUES
("BIO101", "BIO 101: Introduction to Biology", "course", "BIO 101", "An introductory course covering the fundamentals of biology, cell structure, genetics, and evolution. Includes laboratory sessions and field work.", NULL, NULL, 1, 0, 0, NULL, 0, NULL, "admin", "admin", NOW(), NOW(), 0, 0, 0),
("HIST201", "HIST 201: World History", "course", "HIST 201", "A comprehensive survey of world history from ancient civilizations to the modern era. Covers political, social, and cultural developments.", NULL, NULL, 1, 0, 0, NULL, 0, NULL, "admin", "admin", NOW(), NOW(), 0, 0, 0),
("CS110", "CS 110: Computer Science Fundamentals", "course", "CS 110", "Introduction to programming concepts, algorithms, and data structures using Python.", NULL, NULL, 1, 0, 0, NULL, 0, NULL, "admin", "admin", NOW(), NOW(), 0, 0, 0),
("CHEM301", "CHEM 301: Organic Chemistry", "course", "CHEM 301", "Advanced study of carbon-based compounds, reaction mechanisms, stereochemistry, and spectroscopic methods.", NULL, NULL, 1, 0, 0, NULL, 0, NULL, "admin", "admin", NOW(), NOW(), 0, 0, 0);

-- Add admin as maintainer
INSERT IGNORE INTO SAKAI_SITE_USER (SITE_ID, USER_ID, PERMISSION) VALUES
("BIO101", "admin", -1), ("HIST201", "admin", -1), ("CS110", "admin", -1), ("CHEM301", "admin", -1);

-- Add pages with tools for each course
INSERT IGNORE INTO SAKAI_SITE_PAGE (PAGE_ID, SITE_ID, TITLE, LAYOUT, SITE_ORDER, POPUP) VALUES
(UUID(), "BIO101", "Announcements", "0", 1, "0"), (UUID(), "BIO101", "Assignments", "0", 2, "0"),
(UUID(), "BIO101", "Gradebook", "0", 3, "0"), (UUID(), "BIO101", "Resources", "0", 4, "0"),
(UUID(), "BIO101", "Syllabus", "0", 5, "0"), (UUID(), "BIO101", "Tests & Quizzes", "0", 6, "0"),
(UUID(), "BIO101", "Forums", "0", 7, "0"),
(UUID(), "HIST201", "Announcements", "0", 1, "0"), (UUID(), "HIST201", "Assignments", "0", 2, "0"),
(UUID(), "HIST201", "Gradebook", "0", 3, "0"), (UUID(), "HIST201", "Resources", "0", 4, "0"),
(UUID(), "HIST201", "Syllabus", "0", 5, "0"), (UUID(), "HIST201", "Forums", "0", 7, "0"),
(UUID(), "CS110", "Announcements", "0", 1, "0"), (UUID(), "CS110", "Assignments", "0", 2, "0"),
(UUID(), "CS110", "Resources", "0", 4, "0"),
(UUID(), "CHEM301", "Announcements", "0", 1, "0"), (UUID(), "CHEM301", "Assignments", "0", 2, "0"),
(UUID(), "CHEM301", "Gradebook", "0", 3, "0"), (UUID(), "CHEM301", "Resources", "0", 4, "0"),
(UUID(), "CHEM301", "Syllabus", "0", 5, "0"), (UUID(), "CHEM301", "Tests & Quizzes", "0", 6, "0");

-- Add tool registrations to each page
INSERT IGNORE INTO SAKAI_SITE_TOOL (TOOL_ID, PAGE_ID, SITE_ID, REGISTRATION, TITLE, LAYOUT_HINTS, PAGE_ORDER)
SELECT UUID(), PAGE_ID, SITE_ID,
    CASE TITLE
        WHEN "Announcements" THEN "sakai.announcements"
        WHEN "Assignments" THEN "sakai.assignment.grades"
        WHEN "Gradebook" THEN "sakai.gradebookng"
        WHEN "Resources" THEN "sakai.resources"
        WHEN "Syllabus" THEN "sakai.syllabus"
        WHEN "Tests & Quizzes" THEN "sakai.samigo"
        WHEN "Forums" THEN "sakai.forums"
    END,
    TITLE, NULL, 0
FROM SAKAI_SITE_PAGE
WHERE SITE_ID IN ("BIO101", "HIST201", "CS110", "CHEM301");
EOSQL

# Verify seeding
SITE_COUNT=$(docker exec sakai-db mysql -u sakai -psakaipass sakai -N -e "SELECT COUNT(*) FROM SAKAI_SITE WHERE SITE_ID IN ('BIO101','HIST201','CS110','CHEM301')" 2>/dev/null)
TOOL_COUNT=$(docker exec sakai-db mysql -u sakai -psakaipass sakai -N -e "SELECT COUNT(*) FROM SAKAI_SITE_TOOL WHERE SITE_ID IN ('BIO101','HIST201','CS110','CHEM301')" 2>/dev/null)
echo "Seeded $SITE_COUNT course sites with $TOOL_COUNT total tools"

if [ "${SITE_COUNT:-0}" -lt 4 ]; then
    echo "ERROR: Course seeding failed! Expected 4 sites, got $SITE_COUNT"
    exit 1
fi
echo "Demo data seeding complete"

# ============================================================
# 6. Copy real data files into accessible locations
# ============================================================
echo "--- Deploying real data files ---"
mkdir -p /home/ga/Documents/course_materials
cp /workspace/data/*.txt /home/ga/Documents/course_materials/ 2>/dev/null || true
cp /workspace/data/*.csv /home/ga/Documents/course_materials/ 2>/dev/null || true
chown -R ga:ga /home/ga/Documents

# ============================================================
# 7. Set up Firefox profile
# ============================================================
echo "--- Setting up Firefox profile ---"
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

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

cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'USERJS'
// Disable first-run screens
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to Sakai
user_pref("browser.startup.homepage", "http://localhost:8080/portal");
user_pref("browser.startup.page", 1);

// Disable updates
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable sidebar and popups
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
cat > /home/ga/Desktop/Sakai.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Sakai LMS
Comment=Learning Management System
Exec=firefox http://localhost:8080/portal
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Education;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/Sakai.desktop
chmod +x /home/ga/Desktop/Sakai.desktop

# ============================================================
# 8. Create utility script for database queries
# ============================================================
cat > /usr/local/bin/sakai-db-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against Sakai database via Docker
docker exec sakai-db mysql -u sakai -psakaipass sakai -e "$1"
DBQUERYEOF
chmod +x /usr/local/bin/sakai-db-query

cat > /usr/local/bin/sakai-db-query-raw << 'DBRAWEOF'
#!/bin/bash
# Execute SQL query against Sakai database (no headers, tab-separated)
docker exec sakai-db mysql -u sakai -psakaipass sakai -N -B -e "$1"
DBRAWEOF
chmod +x /usr/local/bin/sakai-db-query-raw

# ============================================================
# 9. Create auto-login helper and launch Firefox
# ============================================================
echo "--- Re-verifying Sakai before launching Firefox ---"
for i in $(seq 1 60); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SAKAI_URL" 2>/dev/null || echo "000")
    if echo "$HTTP_CODE" | grep -qE "200|302|301"; then
        echo "Sakai web service ready (HTTP $HTTP_CODE)"
        break
    fi
    sleep 5
done

# Create auto-login helper page (snap Firefox needs files in ~/)
mkdir -p /home/ga/snap/firefox/common
cat > /home/ga/snap/firefox/common/sakai_login.html << 'LOGINEOF'
<html><body onload="document.forms[0].submit()">
<form method="post" action="http://localhost:8080/portal/xlogin">
<input name="eid" value="admin"><input name="pw" value="admin">
</form></body></html>
LOGINEOF
chown -R ga:ga /home/ga/snap

echo "Launching Firefox with auto-login..."
su - ga -c "export DISPLAY=:1 && setsid firefox /home/ga/snap/firefox/common/sakai_login.html > /tmp/firefox_sakai.log 2>&1 &"

# Wait for Firefox window (snap Firefox takes 15-30s to start)
FIREFOX_STARTED=false
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|sakai"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    sleep 5
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# NOTE: auto.ddl is left as-is. It will be disabled by the checkpoint system
# after first successful boot (the config is baked into the disk checkpoint).

echo ""
echo "=== Sakai Setup Complete ==="
echo ""
echo "Sakai is running at: $SAKAI_URL"
echo ""
echo "Login Credentials:"
echo "  Admin:      ${ADMIN_USER} / ${ADMIN_PASS}"
echo "  Instructor: instructor / sakai"
echo "  Students:   student0001-student0500 / sakai"
echo ""
echo "Pre-loaded Data:"
echo "  Courses: BIO101, HIST201, CS110, CHEM301"
echo "  Users: Demo users from SampleUserDirectoryProvider"
echo "  Enrollments: 10 students per course, instructors assigned"
echo ""
echo "Database access:"
echo "  sakai-db-query \"SELECT SITE_ID, TITLE FROM SAKAI_SITE\""
echo ""
