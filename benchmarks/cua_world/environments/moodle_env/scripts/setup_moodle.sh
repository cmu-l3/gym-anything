#!/bin/bash
# Moodle Setup Script (post_start hook)
# Starts MariaDB (Docker or native), runs Moodle CLI installer, generates test data, launches Firefox
#
# Default credentials: admin / Admin1234!

echo "=== Setting up Moodle ==="

# Configuration
MOODLE_DIR="/var/www/html/moodle"
MOODLE_DATA="/var/moodledata"
MOODLE_URL="http://localhost/"
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
DB_NAME="moodle"
DB_USER="moodleuser"
DB_PASS="moodlepass"

# Will be set based on which database method succeeds
DB_HOST=""
MARIADB_METHOD=""

# Function to wait for MariaDB to be ready (Docker version)
wait_for_mariadb_docker() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for MariaDB Docker to be ready..."

    while [ $elapsed -lt $timeout ]; do
        if docker exec moodle-mariadb mysqladmin ping -h localhost -uroot -prootpass 2>/dev/null | grep -q "alive"; then
            echo "MariaDB Docker is ready after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo "  Waiting for MariaDB Docker... ${elapsed}s"
    done

    echo "WARNING: MariaDB Docker readiness check timed out after ${timeout}s"
    return 1
}

# Function to wait for native MariaDB
wait_for_mariadb_native() {
    local timeout=${1:-60}
    local elapsed=0

    echo "Waiting for native MariaDB to be ready..."

    while [ $elapsed -lt $timeout ]; do
        if mysqladmin ping -h localhost 2>/dev/null | grep -q "alive"; then
            echo "Native MariaDB is ready after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo "  Waiting for native MariaDB... ${elapsed}s"
    done

    echo "WARNING: Native MariaDB readiness check timed out after ${timeout}s"
    return 1
}

# Function to wait for Moodle web to be ready
wait_for_moodle() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for Moodle web interface to be ready..."

    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$MOODLE_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "303" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "Moodle web is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done

    echo "WARNING: Moodle readiness check timed out after ${timeout}s"
    return 1
}

# ============================================================
# 1. Start MariaDB (Try Docker first, fall back to native)
# ============================================================
echo "Setting up MariaDB database..."

# Try Docker-based MariaDB first
echo "Attempting to start MariaDB via Docker..."
mkdir -p /home/ga/moodle
cp /workspace/config/docker-compose.yml /home/ga/moodle/
chown -R ga:ga /home/ga/moodle

cd /home/ga/moodle
DOCKER_PULL_RESULT=$(docker-compose pull 2>&1)
DOCKER_PULL_EXIT=$?

if [ $DOCKER_PULL_EXIT -eq 0 ]; then
    docker-compose up -d
    if wait_for_mariadb_docker 120; then
        echo "MariaDB Docker started successfully"
        MARIADB_METHOD="docker"
        DB_HOST="127.0.0.1"
        echo "MariaDB container status:"
        docker-compose ps
    else
        echo "MariaDB Docker failed to start, falling back to native installation"
        docker-compose down 2>/dev/null || true
    fi
else
    echo "Docker pull failed (possibly rate limited): $DOCKER_PULL_RESULT"
    echo "Falling back to native MariaDB installation..."
fi

# Fall back to native MariaDB if Docker failed
if [ -z "$MARIADB_METHOD" ]; then
    echo ""
    echo "Installing MariaDB natively..."
    apt-get update
    apt-get install -y mariadb-server

    systemctl start mariadb
    systemctl enable mariadb

    # Create database and user
    mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"

    if wait_for_mariadb_native 60; then
        echo "Native MariaDB installed and started successfully"
        MARIADB_METHOD="native"
        DB_HOST="localhost"
    else
        echo "ERROR: Neither Docker nor native MariaDB could be started"
        exit 1
    fi
fi

# Save the method for task_utils.sh to use
echo "$MARIADB_METHOD" > /tmp/mariadb_method
echo "$DB_HOST" > /tmp/mariadb_host

# ============================================================
# 2. Install Moodle via CLI
# ============================================================
echo ""
echo "Running Moodle CLI installer..."

# Ensure correct permissions
chown -R www-data:www-data "$MOODLE_DIR"
chown -R www-data:www-data "$MOODLE_DATA"
chmod -R 755 "$MOODLE_DIR"
chmod 777 "$MOODLE_DATA"

# Run the Moodle installer as www-data from the Moodle directory
# (avoids chdir permission denied error)
# This creates config.php and sets up the database schema
cd "$MOODLE_DIR"
sudo -u www-data php admin/cli/install.php \
    --wwwroot="http://localhost" \
    --dataroot="$MOODLE_DATA" \
    --dbtype=mariadb \
    --dbhost="$DB_HOST" \
    --dbname="$DB_NAME" \
    --dbuser="$DB_USER" \
    --dbpass="$DB_PASS" \
    --adminuser="$ADMIN_USER" \
    --adminpass="$ADMIN_PASS" \
    --adminemail="admin@example.com" \
    --fullname="Moodle LMS" \
    --shortname="moodle" \
    --agree-license \
    --non-interactive 2>&1
cd /

INSTALL_EXIT=$?
if [ $INSTALL_EXIT -ne 0 ]; then
    echo "WARNING: Moodle CLI installer exited with code $INSTALL_EXIT"
    echo "Checking if config.php exists (may already be installed)..."
    if [ -f "$MOODLE_DIR/config.php" ]; then
        echo "config.php exists - Moodle may already be installed"
    else
        echo "ERROR: config.php not found. Installation failed."
        echo "Attempting manual config.php creation..."
        cat > "$MOODLE_DIR/config.php" << CONFIGEOF
<?php
unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

\$CFG->dbtype    = 'mariadb';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = '$DB_HOST';
\$CFG->dbname    = '$DB_NAME';
\$CFG->dbuser    = '$DB_USER';
\$CFG->dbpass    = '$DB_PASS';
\$CFG->prefix    = 'mdl_';
\$CFG->dboptions = array(
    'dbpersist' => 0,
    'dbsocket'  => '',
    'dbcollation' => 'utf8mb4_unicode_ci',
);

\$CFG->wwwroot   = 'http://localhost';
\$CFG->dataroot  = '$MOODLE_DATA';
\$CFG->admin     = 'admin';

\$CFG->directorypermissions = 0777;

require_once(__DIR__ . '/lib/setup.php');
CONFIGEOF
        chown www-data:www-data "$MOODLE_DIR/config.php"
    fi
fi

# ============================================================
# 3. Start Apache
# ============================================================
echo ""
echo "Starting Apache..."
systemctl restart apache2

# Wait for Moodle to be accessible
wait_for_moodle 120

# ============================================================
# 4. Generate test data
# ============================================================
echo ""
echo "Generating realistic test data..."
sleep 5

# Create course categories using Moodle PHP API
echo "Creating course categories..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('$MOODLE_DIR/config.php');

// Create Science category
\$data = new stdClass();
\$data->name = 'Science';
\$data->idnumber = 'SCI';
\$data->description = 'Science Department courses';
try { \core_course_category::create(\$data); echo \"Created Science category\n\"; } catch (Exception \$e) { echo 'Science: ' . \$e->getMessage() . \"\n\"; }

// Create Humanities category
\$data2 = new stdClass();
\$data2->name = 'Humanities';
\$data2->idnumber = 'HUM';
\$data2->description = 'Humanities Department courses';
try { \core_course_category::create(\$data2); echo \"Created Humanities category\n\"; } catch (Exception \$e) { echo 'Humanities: ' . \$e->getMessage() . \"\n\"; }

// Create Engineering category
\$data3 = new stdClass();
\$data3->name = 'Engineering';
\$data3->idnumber = 'ENG';
\$data3->description = 'Engineering Department courses';
try { \core_course_category::create(\$data3); echo \"Created Engineering category\n\"; } catch (Exception \$e) { echo 'Engineering: ' . \$e->getMessage() . \"\n\"; }
" 2>&1 || echo "Note: Category creation had issues"

# Create test users
echo "Creating test users..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('$MOODLE_DIR/config.php');
require_once(\$CFG->dirroot . '/user/lib.php');

\$users = [
    ['username'=>'jsmith', 'firstname'=>'Jane', 'lastname'=>'Smith', 'email'=>'jsmith@example.com', 'password'=>'Student1234!'],
    ['username'=>'mjones', 'firstname'=>'Michael', 'lastname'=>'Jones', 'email'=>'mjones@example.com', 'password'=>'Student1234!'],
    ['username'=>'awilson', 'firstname'=>'Alice', 'lastname'=>'Wilson', 'email'=>'awilson@example.com', 'password'=>'Student1234!'],
    ['username'=>'bbrown', 'firstname'=>'Bob', 'lastname'=>'Brown', 'email'=>'bbrown@example.com', 'password'=>'Student1234!'],
    ['username'=>'cgarcia', 'firstname'=>'Carlos', 'lastname'=>'Garcia', 'email'=>'cgarcia@example.com', 'password'=>'Student1234!'],
    ['username'=>'dlee', 'firstname'=>'Diana', 'lastname'=>'Lee', 'email'=>'dlee@example.com', 'password'=>'Student1234!'],
    ['username'=>'epatel', 'firstname'=>'Emily', 'lastname'=>'Patel', 'email'=>'epatel@example.com', 'password'=>'Student1234!'],
    ['username'=>'fkim', 'firstname'=>'Frank', 'lastname'=>'Kim', 'email'=>'fkim@example.com', 'password'=>'Student1234!'],
    ['username'=>'teacher1', 'firstname'=>'Professor', 'lastname'=>'Anderson', 'email'=>'teacher1@example.com', 'password'=>'Teacher1234!'],
    ['username'=>'teacher2', 'firstname'=>'Dr.', 'lastname'=>'Martinez', 'email'=>'teacher2@example.com', 'password'=>'Teacher1234!'],
];

foreach (\$users as \$u) {
    \$user = new stdClass();
    \$user->username = \$u['username'];
    \$user->firstname = \$u['firstname'];
    \$user->lastname = \$u['lastname'];
    \$user->email = \$u['email'];
    \$user->password = \$u['password'];
    \$user->auth = 'manual';
    \$user->confirmed = 1;
    \$user->mnethostid = \$CFG->mnet_localhost_id;
    try {
        \$id = user_create_user(\$user, true, false);
        echo \"Created user: {\$u['username']} (id=\$id)\n\";
    } catch (Exception \$e) {
        echo \"User {\$u['username']}: \" . \$e->getMessage() . \"\n\";
    }
}
" 2>&1 || echo "Note: Some users may already exist"

# Create sample courses
echo "Creating sample courses..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('$MOODLE_DIR/config.php');
require_once(\$CFG->dirroot . '/course/lib.php');

// Get category IDs
\$sci_cat = \$DB->get_record('course_categories', ['idnumber' => 'SCI']);
\$hum_cat = \$DB->get_record('course_categories', ['idnumber' => 'HUM']);
\$eng_cat = \$DB->get_record('course_categories', ['idnumber' => 'ENG']);

\$sci_id = \$sci_cat ? \$sci_cat->id : 1;
\$hum_id = \$hum_cat ? \$hum_cat->id : 1;
\$eng_id = \$eng_cat ? \$eng_cat->id : 1;

\$courses = [
    ['fullname'=>'Introduction to Biology', 'shortname'=>'BIO101', 'category'=>\$sci_id, 'summary'=>'An introductory course covering the fundamentals of biology, cell structure, genetics, and evolution.'],
    ['fullname'=>'World History', 'shortname'=>'HIST201', 'category'=>\$hum_id, 'summary'=>'A comprehensive survey of world history from ancient civilizations to the modern era.'],
    ['fullname'=>'Computer Science Fundamentals', 'shortname'=>'CS110', 'category'=>\$eng_id, 'summary'=>'Introduction to programming concepts, algorithms, and data structures.'],
];

foreach (\$courses as \$c) {
    \$course = new stdClass();
    \$course->fullname = \$c['fullname'];
    \$course->shortname = \$c['shortname'];
    \$course->category = \$c['category'];
    \$course->summary = \$c['summary'];
    \$course->format = 'topics';
    \$course->numsections = 10;
    \$course->visible = 1;
    \$course->startdate = time();
    try {
        \$created = create_course(\$course);
        echo \"Created course: {\$c['shortname']} (id={\$created->id})\n\";
    } catch (Exception \$e) {
        echo \"Course {\$c['shortname']}: \" . \$e->getMessage() . \"\n\";
    }
}
" 2>&1 || echo "Note: Some courses may already exist"

# Enroll teachers and some students
echo "Enrolling users in sample courses..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('$MOODLE_DIR/config.php');
require_once(\$CFG->libdir . '/enrollib.php');

// Get course and user IDs
\$bio = \$DB->get_record('course', ['shortname' => 'BIO101']);
\$hist = \$DB->get_record('course', ['shortname' => 'HIST201']);
\$cs = \$DB->get_record('course', ['shortname' => 'CS110']);
\$teacher1 = \$DB->get_record('user', ['username' => 'teacher1']);
\$teacher2 = \$DB->get_record('user', ['username' => 'teacher2']);

// Get manual enrollment plugin
\$enrol = enrol_get_plugin('manual');

if (\$bio && \$teacher1) {
    \$instances = enrol_get_instances(\$bio->id, true);
    foreach (\$instances as \$inst) {
        if (\$inst->enrol === 'manual') {
            \$enrol->enrol_user(\$inst, \$teacher1->id, 3); // role 3 = editingteacher
            echo \"Enrolled teacher1 in BIO101\n\";
            // Enroll first 3 students
            foreach (['jsmith','mjones','awilson'] as \$uname) {
                \$u = \$DB->get_record('user', ['username' => \$uname]);
                if (\$u) { \$enrol->enrol_user(\$inst, \$u->id, 5); echo \"Enrolled \$uname in BIO101\n\"; }
            }
            break;
        }
    }
}

if (\$hist && \$teacher2) {
    \$instances = enrol_get_instances(\$hist->id, true);
    foreach (\$instances as \$inst) {
        if (\$inst->enrol === 'manual') {
            \$enrol->enrol_user(\$inst, \$teacher2->id, 3);
            echo \"Enrolled teacher2 in HIST201\n\";
            foreach (['bbrown','cgarcia','dlee'] as \$uname) {
                \$u = \$DB->get_record('user', ['username' => \$uname]);
                if (\$u) { \$enrol->enrol_user(\$inst, \$u->id, 5); echo \"Enrolled \$uname in HIST201\n\"; }
            }
            break;
        }
    }
}
" 2>&1 || echo "Note: Enrollment setup may have partial failures"

echo ""
echo "Test data generation complete."

# ============================================================
# 5. Set up Firefox profile for user 'ga'
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

// Set homepage to Moodle
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
cat > /home/ga/Desktop/Moodle.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Moodle LMS
Comment=Learning Management System
Exec=firefox http://localhost/
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Education;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/Moodle.desktop
chmod +x /home/ga/Desktop/Moodle.desktop

# Create utility script for database queries (detects Docker vs native)
cat > /usr/local/bin/moodle-db-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against Moodle database
# Automatically detects whether to use Docker or native MariaDB

MARIADB_METHOD=$(cat /tmp/mariadb_method 2>/dev/null || echo "native")

if [ "$MARIADB_METHOD" = "docker" ]; then
    docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -e "$1"
else
    mysql -u moodleuser -pmoodlepass moodle -e "$1"
fi
DBQUERYEOF
chmod +x /usr/local/bin/moodle-db-query

# ============================================================
# 6. Re-verify Moodle and launch Firefox
# ============================================================
echo "Re-verifying Moodle is responsive before launching Firefox..."
for i in $(seq 1 60); do
    if curl -s -o /dev/null -w "%{http_code}" "$MOODLE_URL" 2>/dev/null | grep -qE "200|302|303"; then
        echo "Moodle web service ready"
        break
    fi
    sleep 2
done

echo "Launching Firefox with Moodle..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/' > /tmp/firefox_moodle.log 2>&1 &"

# Wait for Firefox window
sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|moodle"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    sleep 2
    # Maximize Firefox window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

echo ""
echo "=== Moodle Setup Complete ==="
echo ""
echo "MariaDB Method: $MARIADB_METHOD"
echo "Database Host: $DB_HOST"
echo "Moodle is running at: $MOODLE_URL"
echo ""
echo "Login Credentials:"
echo "  Admin: ${ADMIN_USER} / ${ADMIN_PASS}"
echo "  Teacher: teacher1 / Teacher1234!"
echo "  Student: jsmith / Student1234!"
echo ""
echo "Pre-loaded Data:"
echo "  Categories: Science, Humanities, Engineering"
echo "  Courses: BIO101, HIST201, CS110"
echo "  Users: 8 students + 2 teachers + 1 admin"
echo ""
echo "Database access:"
echo "  moodle-db-query \"SELECT COUNT(*) FROM mdl_course\""
echo ""
