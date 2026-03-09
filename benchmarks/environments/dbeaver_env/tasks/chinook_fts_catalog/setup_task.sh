#!/bin/bash
# Setup script for chinook_fts_catalog task
# Prepares clean state: Chinook DB exists, no pre-existing FTS table

set -e
echo "=== Setting up Chinook FTS Catalog Task ==="

source /workspace/scripts/task_utils.sh

CHINOOK_DB="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# 1. Ensure Chinook database is present
if [ ! -f "$CHINOOK_DB" ]; then
    echo "Chinook database not found, running global setup..."
    /workspace/scripts/setup_dbeaver.sh
fi

# 2. Clean up any previous attempts (Anti-Gaming)
# Remove the FTS table if it exists to force the agent to create it
if [ -f "$CHINOOK_DB" ]; then
    echo "Cleaning up existing FTS tables..."
    sqlite3 "$CHINOOK_DB" "DROP TABLE IF EXISTS catalog_fts;"
    # Also drop any shadow tables created by FTS5
    sqlite3 "$CHINOOK_DB" "DROP TABLE IF EXISTS catalog_fts_data;"
    sqlite3 "$CHINOOK_DB" "DROP TABLE IF EXISTS catalog_fts_idx;"
    sqlite3 "$CHINOOK_DB" "DROP TABLE IF EXISTS catalog_fts_content;"
    sqlite3 "$CHINOOK_DB" "DROP TABLE IF EXISTS catalog_fts_docsize;"
    sqlite3 "$CHINOOK_DB" "DROP TABLE IF EXISTS catalog_fts_config;"
fi

# Remove previous export files
rm -f "$EXPORT_DIR/search_iron_maiden.csv"
rm -f "$EXPORT_DIR/search_blues_rock.csv"
rm -f "$EXPORT_DIR/search_bach.csv"
rm -f "$SCRIPTS_DIR/fts_catalog_setup.sql"

# 3. Record initial state
date +%s > /tmp/task_start_time.txt

# Record initial table count
sqlite3 "$CHINOOK_DB" "SELECT count(*) FROM sqlite_master WHERE type='table'" > /tmp/initial_table_count.txt

# 4. Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# 5. Focus DBeaver and take screenshot
focus_dbeaver
take_screenshot /tmp/fts_initial.png

echo "=== Setup Complete ==="
echo "Database: $CHINOOK_DB"
echo "Target Table: catalog_fts"