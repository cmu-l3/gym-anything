#!/bin/bash
set -e

echo "=== Setting up SeisComP ==="

export SEISCOMP_ROOT=/home/ga/seiscomp
export PATH="$SEISCOMP_ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$SEISCOMP_ROOT/lib:$LD_LIBRARY_PATH"
export PYTHONPATH="$SEISCOMP_ROOT/lib/python:$PYTHONPATH"

# ─── 1. Wait for desktop to be ready ─────────────────────────────────────────

echo "--- Waiting for desktop ---"
sleep 5

# ─── 2. Ensure MariaDB is running ────────────────────────────────────────────

echo "--- Ensuring MariaDB is running ---"
systemctl start mariadb || true

for i in $(seq 1 30); do
    if mysqladmin ping -h localhost 2>/dev/null; then
        echo "MariaDB is ready"
        break
    fi
    sleep 2
done

# Create SeisComP database, user, and import schema
echo "Setting up SeisComP database..."
mysql -u root << 'SQLEOF'
CREATE DATABASE IF NOT EXISTS seiscomp CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS 'sysop'@'localhost' IDENTIFIED BY 'sysop';
GRANT ALL PRIVILEGES ON seiscomp.* TO 'sysop'@'localhost';
FLUSH PRIVILEGES;
SQLEOF

# Import schema if not already done
TABLE_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='seiscomp'" 2>/dev/null || echo "0")
if [ "$TABLE_COUNT" = "0" ] && [ -f "$SEISCOMP_ROOT/share/db/mysql.sql" ]; then
    mysql -u sysop -psysop seiscomp < "$SEISCOMP_ROOT/share/db/mysql.sql"
    echo "Database schema imported"
else
    echo "Database already has $TABLE_COUNT tables"
fi

# ─── 3. Configure SeisComP non-interactively ─────────────────────────────────

echo "--- Configuring SeisComP ---"

mkdir -p "$SEISCOMP_ROOT/etc/defaults"
mkdir -p "$SEISCOMP_ROOT/etc/key"
mkdir -p "$SEISCOMP_ROOT/var/run"
mkdir -p "$SEISCOMP_ROOT/var/lib/archive"
mkdir -p /home/ga/.seiscomp

# Write global config with dbmysql plugin
cat > "$SEISCOMP_ROOT/etc/global.cfg" << 'CFGEOF'
plugins = dbmysql
database = mysql://sysop:sysop@localhost/seiscomp
agencyID = GYM
datacenterID = gym.seiscomp
organization = Gym Anything Seismology Lab
CFGEOF

# Write scmaster config with dbstore plugin for queue-based messaging
cat > "$SEISCOMP_ROOT/etc/scmaster.cfg" << 'CFGEOF'
plugins = dbmysql, dbstore
queues = production
queues.production.groups = AMPLITUDE, PICK, LOCATION, MAGNITUDE, FOCMECH, EVENT, QC, PUBLICATION, GUI, INVENTORY, CONFIG, LOGGING, SERVICE_REQUEST, SERVICE_PROVIDE
queues.production.processors.messages = dbstore
queues.production.processors.messages.dbstore.driver = mysql
queues.production.processors.messages.dbstore.read = sysop:sysop@localhost/seiscomp
queues.production.processors.messages.dbstore.write = sysop:sysop@localhost/seiscomp
CFGEOF

# Remove any conflicting defaults config
rm -f "$SEISCOMP_ROOT/etc/defaults/scmaster.cfg"
rm -f "$SEISCOMP_ROOT/etc/defaults/global.cfg"

# Mark setup as complete (bypass interactive setup wizard)
touch "$SEISCOMP_ROOT/var/run/seiscomp.init"

chown -R ga:ga "$SEISCOMP_ROOT"
chown -R ga:ga /home/ga/.seiscomp

# ─── 4. Start SeisComP scmaster (messaging server) ───────────────────────────

echo "--- Starting scmaster ---"

su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    $SEISCOMP_ROOT/bin/seiscomp start scmaster" || true

# Wait for scmaster to be ready
for i in $(seq 1 15); do
    if su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
        LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
        $SEISCOMP_ROOT/bin/seiscomp status scmaster 2>/dev/null" | grep -q "is running"; then
        echo "scmaster is running"
        break
    fi
    sleep 2
done

# ─── 5. Copy bundled FDSN data (pre-downloaded for reproducibility) ──────────

echo "--- Copying bundled seismic data ---"

DATA_DIR="$SEISCOMP_ROOT/var/lib"
BUNDLED_DIR="/workspace/data/fdsn"
mkdir -p "$DATA_DIR/inventory" "$DATA_DIR/events" "$DATA_DIR/archive"

# 5a. Station inventory (FDSN StationXML from GEOFON, pre-downloaded)
cp "$BUNDLED_DIR/ge_stations.xml" "$DATA_DIR/inventory/ge_stations.xml"
echo "  Station inventory copied ($(wc -c < "$DATA_DIR/inventory/ge_stations.xml") bytes)"

# 5b. Earthquake event data (QuakeML from USGS, pre-downloaded)
cp "$BUNDLED_DIR/noto_earthquake.xml" "$DATA_DIR/events/noto_earthquake.xml"
echo "  Event data copied ($(wc -c < "$DATA_DIR/events/noto_earthquake.xml") bytes)"

# 5c. Waveform data (miniSEED from GEOFON, pre-downloaded)
for MSEED in "$BUNDLED_DIR"/GE.*.mseed; do
    [ -f "$MSEED" ] || continue
    cp "$MSEED" "$DATA_DIR/archive/$(basename "$MSEED")"
    echo "  Waveform copied: $(basename "$MSEED") ($(wc -c < "$MSEED") bytes)"
done

chown -R ga:ga "$DATA_DIR"

# ─── 6. Import station inventory into SeisComP ───────────────────────────────

echo "--- Importing station inventory ---"

if [ -s "$DATA_DIR/inventory/ge_stations.xml" ]; then
    # Convert FDSN StationXML to SeisComP XML format
    su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
        LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
        $SEISCOMP_ROOT/bin/fdsnxml2inv $DATA_DIR/inventory/ge_stations.xml \
        $DATA_DIR/inventory/ge_stations.scml" 2>/dev/null && \
        echo "  Inventory converted to SCML" || true

    # Import converted inventory into database
    if [ -s "$DATA_DIR/inventory/ge_stations.scml" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            $SEISCOMP_ROOT/bin/seiscomp exec scdb --plugins dbmysql \
            -i $DATA_DIR/inventory/ge_stations.scml \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null && \
            echo "  Station inventory imported into database" || \
            echo "  WARN: Inventory import failed"

        # Copy inventory to etc/inventory/ for scconfig Bindings panel
        cp "$DATA_DIR/inventory/ge_stations.scml" "$SEISCOMP_ROOT/etc/inventory/ge_stations.xml"
        chown ga:ga "$SEISCOMP_ROOT/etc/inventory/ge_stations.xml"
        echo "  Inventory copied to etc/inventory/ for scconfig"

        # Create station key files directly (so stations appear in scconfig Bindings)
        mkdir -p "$SEISCOMP_ROOT/etc/key"
        for STA in TOLI GSI KWP SANI BKB; do
            touch "$SEISCOMP_ROOT/etc/key/station_GE_${STA}"
        done
        chown -R ga:ga "$SEISCOMP_ROOT/etc/key"
        echo "  Station key files created for scconfig Bindings"
    fi
fi

# ─── 7. Import event data into SeisComP ──────────────────────────────────────

echo "--- Importing event data ---"

if [ -s "$DATA_DIR/events/noto_earthquake.xml" ]; then
    # Convert USGS QuakeML to SeisComP XML using Python
    su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
        LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
        PYTHONPATH=$SEISCOMP_ROOT/lib/python:\$PYTHONPATH \
        python3 /workspace/scripts/convert_quakeml.py \
        $DATA_DIR/events/noto_earthquake.xml \
        $DATA_DIR/events/noto_earthquake.scml" 2>/dev/null && \
        echo "  Event data converted to SCML" || \
        echo "  WARN: QuakeML conversion failed"

    # Import converted event data into database
    if [ -s "$DATA_DIR/events/noto_earthquake.scml" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            $SEISCOMP_ROOT/bin/seiscomp exec scdb --plugins dbmysql \
            -i $DATA_DIR/events/noto_earthquake.scml \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null && \
            echo "  Event data imported into database" || \
            echo "  WARN: Event import failed"
    fi
fi

# Ensure OriginReference exists (links Event to its Origin for scolv Event tab)
echo "--- Ensuring OriginReference linkage ---"
mysql -u sysop -psysop seiscomp << 'SQLEOF'
INSERT IGNORE INTO OriginReference (_oid, _parent_oid, originID)
SELECT
    (SELECT MAX(_oid) FROM PublicObject) + 1,
    e._oid,
    e.preferredOriginID
FROM Event e
WHERE e.preferredOriginID IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM OriginReference r WHERE r._parent_oid = e._oid);
SQLEOF
echo "  OriginReference check done"

# ─── 8. Set up SDS archive structure for waveform data ───────────────────────

echo "--- Setting up SDS waveform archive ---"

SDS_ROOT="$SEISCOMP_ROOT/var/lib/archive"
YEAR=2024
DOY=001

for MSEED in "$DATA_DIR/archive"/GE.*.mseed; do
    [ -f "$MSEED" ] || continue
    BASENAME=$(basename "$MSEED" .mseed)
    NET=$(echo "$BASENAME" | cut -d. -f1)
    STA=$(echo "$BASENAME" | cut -d. -f2)
    CHA=$(echo "$BASENAME" | cut -d. -f4)

    SDS_DIR="$SDS_ROOT/$YEAR/$NET/$STA/${CHA}.D"
    mkdir -p "$SDS_DIR"
    cp "$MSEED" "$SDS_DIR/${NET}.${STA}..${CHA}.D.${YEAR}.${DOY}"
    echo "  Archived: $NET.$STA.$CHA"
done

chown -R ga:ga "$SDS_ROOT"

# ─── 9. Suppress first-run dialogs for SeisComP GUI apps ─────────────────────

echo "--- Configuring GUI preferences ---"

mkdir -p /home/ga/.seiscomp
cat > /home/ga/.seiscomp/scconfig.cfg << 'EOF'
showWelcome = false
EOF

# Set scolv to load events from last 1000 days (our event is from 2024)
cat > "$SEISCOMP_ROOT/etc/scolv.cfg" << 'EOF'
loadEventDB = 1000
EOF

chown -R ga:ga /home/ga/.seiscomp
chown -R ga:ga "$SEISCOMP_ROOT/etc"

# ─── 10. Create desktop launchers ────────────────────────────────────────────

echo "--- Creating desktop launchers ---"

mkdir -p /home/ga/Desktop

cat > /home/ga/Desktop/scolv.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=SeisComP scolv
Comment=Origin Locator View
Exec=bash -c "source /home/ga/.bashrc && DISPLAY=:1 scolv"
Icon=utilities-system-monitor
Terminal=false
Categories=Science;
EOF

cat > /home/ga/Desktop/scconfig.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=SeisComP scconfig
Comment=Configuration Tool
Exec=bash -c "source /home/ga/.bashrc && DISPLAY=:1 scconfig"
Icon=preferences-system
Terminal=false
Categories=Science;
EOF

cat > /home/ga/Desktop/scrttv.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=SeisComP scrttv
Comment=Real-Time Trace View
Exec=bash -c "source /home/ga/.bashrc && DISPLAY=:1 scrttv"
Icon=utilities-system-monitor
Terminal=false
Categories=Science;
EOF

chmod +x /home/ga/Desktop/*.desktop
chown -R ga:ga /home/ga/Desktop

# ─── 11. Log summary of data ─────────────────────────────────────────────────

echo "--- Data summary ---"
echo "Station inventory:"
ls -la "$DATA_DIR/inventory/" 2>/dev/null || echo "  No inventory files"
echo "Events:"
ls -la "$DATA_DIR/events/" 2>/dev/null || echo "  No event files"
echo "Waveforms in SDS archive:"
find "$SDS_ROOT" -name "*.D.*" -type f 2>/dev/null | wc -l
echo "DB Event count:"
mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "  0"
echo "DB Network count:"
mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Network" 2>/dev/null || echo "  0"

echo "=== SeisComP setup complete ==="
