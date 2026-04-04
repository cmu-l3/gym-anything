#!/bin/bash
# Setup script for chinook_acquisition_merger task
# Sets up main DB and creates the source 'acquisitions' DB with raw data

set -e
echo "=== Setting up Chinook Acquisition Merger Task ==="

source /workspace/scripts/task_utils.sh

# Directories
DB_DIR="/home/ga/Documents/databases"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"
mkdir -p "$DB_DIR" "$EXPORT_DIR" "$SCRIPTS_DIR"

# Paths
CHINOOK_DB="$DB_DIR/chinook.db"
ACQ_DB="$DB_DIR/acquisitions.db"

# 1. Ensure Chinook DB exists (using the environment's setup script logic if needed, but usually pre-existing)
if [ ! -f "$CHINOOK_DB" ]; then
    echo "Chinook DB not found, copying from template..."
    # Fallback if standard setup failed
    cp /workspace/data/chinook.db "$CHINOOK_DB" 2>/dev/null || \
    wget -q -O "$CHINOOK_DB" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
fi
chmod 644 "$CHINOOK_DB"

# 2. Create Acquisitions DB with 'leads' table
echo "Creating acquisitions database..."
rm -f "$ACQ_DB"
sqlite3 "$ACQ_DB" <<EOF
CREATE TABLE leads (
    id INTEGER PRIMARY KEY,
    full_name TEXT,
    email TEXT,
    iso_country TEXT
);

-- Insert duplicates (already in Chinook)
INSERT INTO leads (full_name, email, iso_country) VALUES ('Luis Goncalves', 'luisg@embraer.com.br', 'BR'); -- Existing
INSERT INTO leads (full_name, email, iso_country) VALUES ('Leonie Kohler', 'leonekohler@surfeu.de', 'DE'); -- Existing
INSERT INTO leads (full_name, email, iso_country) VALUES ('Francois Tremblay', 'ftremblay@gmail.com', 'CA'); -- Existing

-- Insert new valid leads (to be imported)
INSERT INTO leads (full_name, email, iso_country) VALUES ('Gary Moore', 'gary.moore@example.com', 'US');
INSERT INTO leads (full_name, email, iso_country) VALUES ('Sarah Connor', 's.connor@skynet.net', 'US');
INSERT INTO leads (full_name, email, iso_country) VALUES ('Jean Luc', 'j.luc@starfleet.org', 'CA');
INSERT INTO leads (full_name, email, iso_country) VALUES ('Pablo Escobar', 'p.escobar@cartel.mx', 'MX');
INSERT INTO leads (full_name, email, iso_country) VALUES ('Walter White', 'heisenberg@chem.com', 'US');
INSERT INTO leads (full_name, email, iso_country) VALUES ('Jesse Pinkman', 'jesse@chem.com', 'US');
INSERT INTO leads (full_name, email, iso_country) VALUES ('Saul Goodman', 'saul@law.com', 'US');
INSERT INTO leads (full_name, email, iso_country) VALUES ('Gus Fring', 'gus@pollos.com', 'US');
INSERT INTO leads (full_name, email, iso_country) VALUES ('Mike Ehrmantraut', 'mike@security.com', 'US');
INSERT INTO leads (full_name, email, iso_country) VALUES ('Kim Wexler', 'kim@law.com', 'US');
INSERT INTO leads (full_name, email, iso_country) VALUES ('Lalo Salamanca', 'lalo@cartel.mx', 'MX');
INSERT INTO leads (full_name, email, iso_country) VALUES ('Nacho Varga', 'nacho@cartel.mx', 'MX');
INSERT INTO leads (full_name, email, iso_country) VALUES ('Howard Hamlin', 'howard@hhm.com', 'US');
INSERT INTO leads (full_name, email, iso_country) VALUES ('Chuck McGill', 'chuck@hhm.com', 'US');
INSERT INTO leads (full_name, email, iso_country) VALUES ('Rick Grimes', 'rick@twd.com', 'US');
EOF
chmod 644 "$ACQ_DB"
chown ga:ga "$ACQ_DB" "$CHINOOK_DB"

# 3. Record Initial State
INITIAL_CUST_COUNT=$(sqlite3 "$CHINOOK_DB" "SELECT COUNT(*) FROM customers;")
echo "$INITIAL_CUST_COUNT" > /tmp/initial_cust_count
echo "Initial customer count: $INITIAL_CUST_COUNT"

# Record timestamp
date +%s > /tmp/task_start_time

# 4. Launch DBeaver
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus and Maximize
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="