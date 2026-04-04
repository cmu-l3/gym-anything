#!/bin/bash
# Export script for chinook_composer_normalization
# Inspects database schema, data content, and exported files

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

WORK_DB="/home/ga/Documents/databases/chinook_normalize.db"
EXPORT_CSV="/home/ga/Documents/exports/top_composers.csv"
SQL_SCRIPT="/home/ga/Documents/scripts/normalize_composers.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
GROUND_TRUTH_FILE="/tmp/composer_ground_truth.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Check 1: DBeaver Connection ---
CONNECTION_EXISTS="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    # Loose check for connection name 'ChinookNormalize' pointing to correct DB
    if grep -q "ChinookNormalize" "$DBEAVER_CONFIG" && grep -q "chinook_normalize.db" "$DBEAVER_CONFIG"; then
        CONNECTION_EXISTS="true"
    fi
fi

# --- Check 2: File Existence ---
CSV_EXISTS="false"
CSV_SIZE=0
if [ -f "$EXPORT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$EXPORT_CSV")
fi

SQL_EXISTS="false"
SQL_SIZE=0
if [ -f "$SQL_SCRIPT" ]; then
    SQL_EXISTS="true"
    SQL_SIZE=$(stat -c%s "$SQL_SCRIPT")
fi

# --- Check 3: Database Inspection (Python) ---
# We use Python to rigorously inspect the SQLite file
echo "Inspecting database state..."
python3 << PYEOF
import sqlite3
import json
import csv
import os

result = {
    "connection_exists": "$CONNECTION_EXISTS" == "true",
    "csv_exists": "$CSV_EXISTS" == "true",
    "sql_exists": "$SQL_EXISTS" == "true",
    "sql_size": int("$SQL_SIZE"),
    "timestamp": "$(date +%s)"
}

# Load ground truth
try:
    with open('$GROUND_TRUTH_FILE', 'r') as f:
        gt = json.load(f)
        result["ground_truth"] = gt
except:
    result["ground_truth"] = {}

# Inspect Database
try:
    conn = sqlite3.connect('$WORK_DB')
    c = conn.cursor()
    
    # 1. Check Tables
    tables = [r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
    result["has_composers_table"] = "composers" in tables
    result["has_bridge_table"] = "track_composers" in tables
    
    # 2. Check View
    views = [r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='view'").fetchall()]
    result["has_view"] = "v_track_composers" in views
    
    # 3. Check Row Counts & Schema
    if result["has_composers_table"]:
        result["composers_count"] = c.execute("SELECT COUNT(*) FROM composers").fetchone()[0]
        # Check columns
        cols = [r[1] for r in c.execute("PRAGMA table_info(composers)").fetchall()]
        result["composers_cols"] = cols
        
    if result["has_bridge_table"]:
        result["bridge_count"] = c.execute("SELECT COUNT(*) FROM track_composers").fetchone()[0]
        # Check integrity - orphaned references
        if result["has_composers_table"]:
            orphans_c = c.execute("SELECT COUNT(*) FROM track_composers WHERE ComposerId NOT IN (SELECT ComposerId FROM composers)").fetchone()[0]
            orphans_t = c.execute("SELECT COUNT(*) FROM track_composers WHERE TrackId NOT IN (SELECT TrackId FROM tracks)").fetchone()[0]
            result["orphaned_refs"] = orphans_c + orphans_t
            
            # Check completeness: How many tracks with non-null composers have entries?
            # Note: This is an approximation query
            linked_tracks = c.execute("SELECT COUNT(DISTINCT TrackId) FROM track_composers").fetchone()[0]
            result["linked_tracks_count"] = linked_tracks

    # 4. Check View Functionality
    if result["has_view"]:
        try:
            view_rows = c.execute("SELECT COUNT(*) FROM v_track_composers").fetchone()[0]
            result["view_rows"] = view_rows
        except:
            result["view_rows"] = -1 # View exists but query failed

    conn.close()
    
except Exception as e:
    result["db_error"] = str(e)

# Inspect CSV Content
if result["csv_exists"]:
    try:
        with open('$EXPORT_CSV', 'r') as f:
            reader = csv.reader(f)
            rows = list(reader)
            result["csv_row_count"] = len(rows)
            if len(rows) > 1:
                result["csv_header"] = rows[0]
                result["csv_top_row"] = rows[1]
    except Exception as e:
        result["csv_error"] = str(e)

# Save result
with open('/tmp/normalization_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Move result to final location for verifier
mv /tmp/normalization_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json