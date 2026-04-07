#!/bin/bash
# Canvas LMS Setup Script (post_start hook)
# Uses the lbjay/canvas-docker fat container which includes all services
#
# Default credentials: canvas@example.edu / canvas-docker

echo "=== Setting up Canvas LMS ==="

# Create swap space to prevent OOM with the fat Docker container
# Canvas LMS bundles Rails + Postgres + Redis + Apache in one container
if [ ! -f /swapfile ]; then
    echo "Creating 4GB swap file..."
    fallocate -l 4G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=4096 2>/dev/null
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "Swap enabled: $(swapon --show)"
else
    swapon /swapfile 2>/dev/null || true
    echo "Swap already exists: $(swapon --show)"
fi

# Configuration for fat container
CANVAS_URL="http://localhost:3000/"
ADMIN_EMAIL="canvas@example.edu"
ADMIN_PASS="canvas-docker"
CONTAINER_NAME="canvas-lms"

CANVAS_METHOD=""

# Function to wait for Canvas container to be ready
wait_for_canvas() {
    local timeout=${1:-300}
    local elapsed=0

    echo "Waiting for Canvas web interface to be ready..."

    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -L "$CANVAS_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
            echo "Canvas web is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done

    echo "WARNING: Canvas readiness check timed out after ${timeout}s"
    return 1
}

# Function to execute database query (fat container version)
canvas_db_query() {
    local query="$1"
    docker exec $CONTAINER_NAME psql -U canvas -d canvas_development -t -A -c "$query" 2>/dev/null
}

# Seed deterministic Canvas test data used by tasks.
seed_canvas_test_data() {
    local retries=3
    local attempt=1

    echo "Seeding Canvas test data..."
    docker cp /workspace/scripts/create_test_data.rb "${CONTAINER_NAME}:/tmp/create_test_data.rb" 2>/dev/null || true

    while [ $attempt -le $retries ]; do
        echo "  Seed attempt ${attempt}/${retries}..."
        local out
        out=$(docker exec "${CONTAINER_NAME}" bash -lc \
            "cd /opt/canvas/canvas-lms && RAILS_ENV=development GEM_HOME=/opt/canvas/.gems /opt/canvas/.gems/bin/bundle exec rails runner /tmp/create_test_data.rb" \
            2>&1 || true)

        # Consider seeding successful if we can verify baseline courses/users exist.
        local course_count
        course_count=$(canvas_db_query "SELECT COUNT(*) FROM courses WHERE workflow_state='available'" | tr -d '[:space:]')
        local user_count
        user_count=$(canvas_db_query "SELECT COUNT(*) FROM users WHERE workflow_state='registered'" | tr -d '[:space:]')

        if [ "${course_count:-0}" -ge 5 ] && [ "${user_count:-0}" -ge 10 ]; then
            echo "  Test data seeded successfully (courses=${course_count}, users=${user_count})."
            return 0
        fi

        echo "  Seed attempt ${attempt} did not produce expected baseline."
        echo "$out" | tail -n 20
        attempt=$((attempt + 1))
        sleep 10
    done

    echo "WARNING: Test data seeding did not reach expected baseline after ${retries} attempts."
    return 1
}

# ============================================================
# 1. Start Canvas via Docker Compose
# ============================================================
echo "Starting Canvas LMS services via Docker..."
mkdir -p /home/ga/canvas
cp /workspace/config/docker-compose.yml /home/ga/canvas/
chown -R ga:ga /home/ga/canvas

cd /home/ga/canvas

# Ensure swap is active (may have been lost on checkpoint restore)
swapon /swapfile 2>/dev/null || true

# Image should already be pulled by install_canvas.sh (pre_start hook)
echo "Docker images available:"
docker images | grep -i canvas || echo "WARNING: Canvas image not found, docker-compose up will pull..."

# Start the container (image already cached, so this is fast)
docker-compose up -d 2>&1
DOCKER_PULL_EXIT=$?
DOCKER_PULL_RESULT="started"

if [ $DOCKER_PULL_EXIT -eq 0 ]; then
    echo "Docker container started successfully"

    # Wait for the fat container to start (it takes time for Rails to boot)
    echo "Waiting for Canvas LMS container to start..."
    sleep 30

    # Show container status
    echo "Container status:"
    docker-compose ps

    # Wait for Canvas to be fully ready (can take 2-3 minutes)
    echo "Waiting for Canvas web to initialize (this may take a few minutes)..."
    if wait_for_canvas 300; then
        echo "Canvas LMS is running!"
        CANVAS_METHOD="docker"
    else
        echo "Canvas may still be initializing. Check docker logs for details."
        echo "Docker logs (last 50 lines):"
        docker logs $CONTAINER_NAME --tail 50 2>&1 || true
        CANVAS_METHOD="docker"  # Still set method even if timed out
    fi
else
    echo "Docker pull failed (possibly rate limited): $DOCKER_PULL_RESULT"
    echo "Falling back to alternative method..."
    CANVAS_METHOD=""
fi

# Save the method for task_utils.sh to use
echo "$CANVAS_METHOD" > /tmp/canvas_method

# ============================================================
# 2. Show Canvas Status
# ============================================================
if [ "$CANVAS_METHOD" = "docker" ]; then
    echo ""
    echo "Checking Canvas database..."
    sleep 5

    # Test database connection - fat container uses canvas_development
    echo "Testing database connection..."
    TABLES=$(docker exec $CONTAINER_NAME psql -U canvas -d canvas_development -c "\\dt" 2>/dev/null | grep -c "public" || echo "0")
    echo "Found $TABLES tables in database"

    # Show existing data counts
    echo ""
    echo "Database status:"
    echo "  Users: $(canvas_db_query "SELECT COUNT(*) FROM users WHERE workflow_state='registered'" || echo "N/A")"
    echo "  Courses: $(canvas_db_query "SELECT COUNT(*) FROM courses WHERE workflow_state='available'" || echo "N/A")"
    echo "  Enrollments: $(canvas_db_query "SELECT COUNT(*) FROM enrollments WHERE workflow_state='active'" || echo "N/A")"

    # Seed task data so tasks have deterministic real entities/courses.
    if seed_canvas_test_data; then
        echo ""
        echo "Database status after seeding:"
        echo "  Users: $(canvas_db_query "SELECT COUNT(*) FROM users WHERE workflow_state='registered'" || echo "N/A")"
        echo "  Courses: $(canvas_db_query "SELECT COUNT(*) FROM courses WHERE workflow_state='available'" || echo "N/A")"
        echo "  Enrollments: $(canvas_db_query "SELECT COUNT(*) FROM enrollments WHERE workflow_state='active'" || echo "N/A")"
    fi
fi

# ============================================================
# 3. Set up Firefox profile for user 'ga'
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

// Set homepage to Canvas LMS
user_pref("browser.startup.homepage", "http://localhost:3000/");
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
cat > /home/ga/Desktop/CanvasLMS.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Canvas LMS
Comment=Learning Management System
Exec=firefox http://localhost:3000/
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Education;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/CanvasLMS.desktop
chmod +x /home/ga/Desktop/CanvasLMS.desktop

# Create utility script for database queries (fat container version)
cat > /usr/local/bin/canvas-db-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against Canvas database
# Usage: canvas-db-query "SELECT * FROM users LIMIT 5;"

docker exec canvas-lms psql -U canvas -d canvas_development -c "$1"
DBQUERYEOF
chmod +x /usr/local/bin/canvas-db-query

# ============================================================
# 4. Launch Firefox
# ============================================================
echo "Launching Firefox with Canvas LMS..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost:3000/' > /tmp/firefox_canvas.log 2>&1 &"

# Wait for Firefox window
sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|canvas"; then
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
echo "=== Canvas LMS Setup Complete ==="
echo ""
echo "Canvas Method: $CANVAS_METHOD"
echo "Canvas is running at: $CANVAS_URL"
echo ""
echo "Login Credentials:"
echo "  Admin: ${ADMIN_EMAIL} / ${ADMIN_PASS}"
echo ""
echo "Database access:"
echo "  canvas-db-query \"SELECT COUNT(*) FROM users;\""
echo ""

# Show Docker container status
if [ "$CANVAS_METHOD" = "docker" ]; then
    echo "Container Status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep canvas || true
fi
