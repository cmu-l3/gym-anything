#!/bin/bash
set -e

echo "=== Setting up GeoServer ==="

GS_URL="http://localhost:8080/geoserver"

# ============================================================
# Setup Docker Compose working directory
# ============================================================
GS_DIR="/home/ga/geoserver"
mkdir -p "$GS_DIR"
cp /workspace/config/docker-compose.yml "$GS_DIR/"
chown -R ga:ga "$GS_DIR"

# ============================================================
# Start Docker services
# ============================================================
cd "$GS_DIR"
docker-compose pull 2>&1 || echo "WARNING: Pull failed, using cached images"
docker-compose up -d

# ============================================================
# Wait for PostGIS to be ready
# ============================================================
wait_for_postgis() {
    local timeout=${1:-120}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker exec gs-postgis pg_isready -U geoserver -d gis 2>/dev/null; then
            echo "PostGIS is ready after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "PostGIS timeout after ${timeout}s"
    return 1
}

echo "Waiting for PostGIS..."
wait_for_postgis 120 || true

# Enable PostGIS extensions (use -h localhost to force TCP/password auth)
docker exec -e PGPASSWORD=geoserver123 gs-postgis psql -U geoserver -h localhost -d gis -c "CREATE EXTENSION IF NOT EXISTS postgis;" 2>/dev/null || true
docker exec -e PGPASSWORD=geoserver123 gs-postgis psql -U geoserver -h localhost -d gis -c "CREATE EXTENSION IF NOT EXISTS postgis_topology;" 2>/dev/null || true

# ============================================================
# Wait for GeoServer to be ready
# ============================================================
wait_for_geoserver() {
    local timeout=${1:-300}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${GS_URL}/web/" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "GeoServer is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        echo "Waiting for GeoServer... (${elapsed}s, HTTP $HTTP_CODE)"
        sleep 10
        elapsed=$((elapsed + 10))
    done
    echo "GeoServer timeout after ${timeout}s"
    docker logs gs-app --tail 50 2>&1
    return 1
}

echo "Waiting for GeoServer..."
wait_for_geoserver 300

# ============================================================
# Verify GeoServer REST API is working
# ============================================================
echo "Verifying GeoServer REST API..."
REST_CHECK=$(curl -s -u admin:Admin123! "${GS_URL}/rest/workspaces.json" 2>/dev/null || echo "FAIL")
echo "REST API check: $REST_CHECK"

# ============================================================
# Import Natural Earth data into PostGIS using ogr2ogr
# ============================================================
echo "=== Importing Natural Earth data into PostGIS ==="

# Copy all shapefiles into the PostGIS container
for prefix in ne_110m_admin_0_countries ne_110m_populated_places ne_110m_rivers_lake_centerlines ne_110m_lakes; do
    for ext in shp shx dbf prj cpg; do
        if [ -f "/home/ga/natural_earth/${prefix}.${ext}" ]; then
            docker cp "/home/ga/natural_earth/${prefix}.${ext}" "gs-postgis:/tmp/"
        fi
    done
done

# Import using ogr2ogr (available in kartoza/postgis)
import_shapefile() {
    local shp_file="$1"
    local table_name="$2"
    echo "Importing ${shp_file} -> ${table_name}..."
    docker exec gs-postgis ogr2ogr \
        -f "PostgreSQL" \
        "PG:host=localhost dbname=gis user=geoserver password=geoserver123" \
        "/tmp/${shp_file}" \
        -nln "${table_name}" \
        -overwrite \
        -lco GEOMETRY_NAME=geom \
        -lco FID=gid \
        -a_srs "EPSG:4326" 2>&1 || echo "WARNING: Failed to import ${shp_file}"
}

# Countries have mixed Polygon/MultiPolygon, need PROMOTE_TO_MULTI
docker exec gs-postgis ogr2ogr \
    -f "PostgreSQL" \
    "PG:host=localhost dbname=gis user=geoserver password=geoserver123" \
    "/tmp/ne_110m_admin_0_countries.shp" \
    -nln "ne_countries" \
    -overwrite \
    -nlt PROMOTE_TO_MULTI \
    -lco GEOMETRY_NAME=geom \
    -lco FID=gid \
    -a_srs "EPSG:4326" 2>&1 || echo "WARNING: Failed to import countries"
import_shapefile "ne_110m_populated_places.shp" "ne_populated_places"
import_shapefile "ne_110m_rivers_lake_centerlines.shp" "ne_rivers"
import_shapefile "ne_110m_lakes.shp" "ne_lakes"

# Verify PostGIS imports
echo "PostGIS tables:"
docker exec -e PGPASSWORD=geoserver123 gs-postgis psql -U geoserver -h localhost -d gis -c "\dt public.*" 2>/dev/null || true

# ============================================================
# Publish Natural Earth layers via GeoServer REST API
# ============================================================
echo "=== Publishing Natural Earth layers in GeoServer ==="

GS_AUTH="admin:Admin123!"

# Create PostGIS data store in the 'ne' workspace
echo "Creating PostGIS data store 'postgis_ne' in workspace 'ne'..."
curl -s -u "$GS_AUTH" -X POST "${GS_URL}/rest/workspaces/ne/datastores" \
    -H "Content-Type: application/json" \
    -d '{
        "dataStore": {
            "name": "postgis_ne",
            "type": "PostGIS",
            "enabled": true,
            "connectionParameters": {
                "entry": [
                    {"@key": "host", "$": "gs-postgis"},
                    {"@key": "port", "$": "5432"},
                    {"@key": "database", "$": "gis"},
                    {"@key": "schema", "$": "public"},
                    {"@key": "user", "$": "geoserver"},
                    {"@key": "passwd", "$": "geoserver123"},
                    {"@key": "dbtype", "$": "postgis"},
                    {"@key": "Expose primary keys", "$": "true"}
                ]
            }
        }
    }' 2>/dev/null && echo "  Data store created" || echo "  WARNING: Data store creation failed"

# Publish each Natural Earth table as a layer
publish_layer() {
    local table_name="$1"
    local layer_title="$2"
    echo "Publishing layer: ${table_name} (${layer_title})..."
    curl -s -u "$GS_AUTH" -X POST "${GS_URL}/rest/workspaces/ne/datastores/postgis_ne/featuretypes" \
        -H "Content-Type: application/json" \
        -d "{
            \"featureType\": {
                \"name\": \"${table_name}\",
                \"title\": \"${layer_title}\",
                \"srs\": \"EPSG:4326\",
                \"nativeBoundingBox\": {
                    \"minx\": -180, \"maxx\": 180,
                    \"miny\": -90, \"maxy\": 90,
                    \"crs\": \"EPSG:4326\"
                },
                \"latLonBoundingBox\": {
                    \"minx\": -180, \"maxx\": 180,
                    \"miny\": -90, \"maxy\": 90,
                    \"crs\": \"EPSG:4326\"
                }
            }
        }" 2>/dev/null && echo "  Published ${table_name}" || echo "  WARNING: Failed to publish ${table_name}"
}

publish_layer "ne_countries" "Natural Earth Countries"
publish_layer "ne_populated_places" "Natural Earth Populated Places"
publish_layer "ne_rivers" "Natural Earth Rivers"
publish_layer "ne_lakes" "Natural Earth Lakes"

# Verify published layers
echo "Verifying published layers..."
PUBLISHED_LAYERS=$(curl -s -u "$GS_AUTH" "${GS_URL}/rest/workspaces/ne/datastores/postgis_ne/featuretypes.json" 2>/dev/null)
echo "Published layers in ne:postgis_ne: $PUBLISHED_LAYERS"

# ============================================================
# Setup Firefox profile
# ============================================================
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

cat > "$FIREFOX_PROFILE_DIR/profiles.ini" << 'EOF'
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
EOF
chown ga:ga "$FIREFOX_PROFILE_DIR/profiles.ini"

cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'EOF'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.homepage", "http://localhost:8080/geoserver/web/");
user_pref("browser.startup.page", 1);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.preferences.moreFromMozilla", false);
user_pref("browser.uitour.enabled", false);
user_pref("sidebar.main.tools", "");
user_pref("sidebar.visibility", "hide-sidebar");
user_pref("browser.sidebar.button", false);
user_pref("sidebar.position_start", false);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.privatebrowsing.vpnpromourl", "");
user_pref("browser.startup.firstrunSkipsHomepage", true);
EOF
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/user.js"
# Also copy to prefs.js — some Firefox versions read prefs.js instead of user.js
cp "$FIREFOX_PROFILE_DIR/default-release/user.js" "$FIREFOX_PROFILE_DIR/default-release/prefs.js"
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/prefs.js"
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# ============================================================
# Create desktop shortcut
# ============================================================
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/GeoServer.desktop << 'EOF'
[Desktop Entry]
Name=GeoServer
Exec=firefox http://localhost:8080/geoserver/web/
Icon=firefox
Type=Application
EOF
chown ga:ga /home/ga/Desktop/GeoServer.desktop
chmod +x /home/ga/Desktop/GeoServer.desktop

# ============================================================
# Launch Firefox (two-phase: create profile, then relaunch clean)
# ============================================================

# Phase 1: Launch Firefox briefly to create the profile directory structure
su - ga -c "DISPLAY=:1 firefox --headless --no-remote 'about:blank' > /tmp/firefox_init.log 2>&1 &"
sleep 5
# Kill the headless instance — its job was to initialize the profile
pkill -u ga -f firefox || true
sleep 2

# Phase 2: Force sidebar prefs into both user.js and prefs.js AFTER profile init
# Firefox may have regenerated prefs.js during phase 1, so overwrite again
cp "$FIREFOX_PROFILE_DIR/default-release/user.js" "$FIREFOX_PROFILE_DIR/default-release/prefs.js"
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/prefs.js"
# Also ensure the sidebar prefs are in prefs.js even if Firefox rewrote it
grep -q "sidebar.revamp" "$FIREFOX_PROFILE_DIR/default-release/prefs.js" || \
    cat >> "$FIREFOX_PROFILE_DIR/default-release/prefs.js" << 'SIDEBAR_EOF'
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("sidebar.main.tools", "");
user_pref("sidebar.visibility", "hide-sidebar");
user_pref("browser.sidebar.button", false);
user_pref("sidebar.position_start", false);
SIDEBAR_EOF

# Phase 3: Launch Firefox for real
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window
sleep 5
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
    echo "Firefox maximized"
fi

# Dismiss any residual sidebar/popups
sleep 3
# Ctrl+F9 / F9 to toggle sidebar off if somehow still open
DISPLAY=:1 xdotool key F9 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key F9 2>/dev/null || true
sleep 0.5
# Press Escape to close any popups/tooltips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
# Click on the main content area to ensure focus is on GeoServer page
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 1

# Take verification screenshot
DISPLAY=:1 import -window root /tmp/setup_verification.png 2>/dev/null || true

echo "=== GeoServer setup complete ==="
echo "GeoServer URL: ${GS_URL}/web/"
echo "Admin credentials: admin / Admin123!"
echo "PostGIS: geoserver / geoserver123 @ localhost:5432/gis"
