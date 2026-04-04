#!/bin/bash
set -e
echo "=== Setting up task: add_cle_presentation ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jurism is running and visible
ensure_jurism_running

# Load some background legal data so the library isn't empty
# This function is defined in task_utils.sh and uses inject_references.py
load_legal_references_to_db

# Clean up any existing items that might match our target to ensure a fresh start
DB_PATH=$(get_jurism_db)
if [ -n "$DB_PATH" ]; then
    echo "Cleaning up potential pre-existing target items in $DB_PATH..."
    
    # 1. Find itemIDs with the target title
    # Field 1 is usually title, but we check generically for the value
    TARGET_IDS=$(sqlite3 "$DB_PATH" "SELECT DISTINCT itemData.itemID FROM itemData JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID WHERE value = 'The Future of Legal Tech: AI and Ethics';" 2>/dev/null)
    
    for id in $TARGET_IDS; do
        if [ -n "$id" ]; then
            echo "Removing existing item ID: $id"
            # Delete from all related tables
            sqlite3 "$DB_PATH" "DELETE FROM itemData WHERE itemID=$id;"
            sqlite3 "$DB_PATH" "DELETE FROM itemCreators WHERE itemID=$id;"
            sqlite3 "$DB_PATH" "DELETE FROM itemNotes WHERE parentItemID=$id;"
            sqlite3 "$DB_PATH" "DELETE FROM items WHERE itemID=$id;"
        fi
    done
    
    # Force a small sleep to ensure DB writes settle
    sleep 1
else
    echo "WARNING: Could not find Jurism database for cleanup"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="