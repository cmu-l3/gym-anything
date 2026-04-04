#!/bin/bash
# pre_task hook for process_order task
# Opens Floreant POS on the main terminal screen (table view)

echo "=== Setting up process_order task ==="

source /workspace/scripts/task_utils.sh

# Restore a clean database to avoid stale orders from previous runs
# (e.g. Table 1 might already have an open order from a prior episode)
kill_floreant
sleep 1
echo "Restoring clean database snapshot..."
DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -n "$DB_POSDB" ] && [ -d /opt/floreantpos/posdb_backup ]; then
    rm -rf "$DB_POSDB"
    cp -r /opt/floreantpos/posdb_backup "$DB_POSDB"
    chown -R ga:ga "$DB_POSDB"
    echo "Database restored from backup (clean state, no prior orders)."
elif [ -d /opt/floreantpos/derby_server_backup ]; then
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Derby server restored from backup (clean state)."
else
    echo "WARNING: No database backup found; proceeding without restore."
fi

# Start Floreant POS and log in
start_and_login

sleep 3

# Take initial screenshot to confirm we're on the main POS screen (table view)
take_screenshot /tmp/floreant_task_start.png
echo "Initial state screenshot saved"

echo "=== process_order task setup complete ==="
echo ""
echo "Task: Place an order for Table 1 with at least 2 menu items"
echo "Steps:"
echo "  1. On the main terminal screen, click 'DINE IN'"
echo "  2. A floor plan / table selection view will appear"
echo "  3. Click on 'Table 1' (or the first available table)"
echo "  4. The order screen opens with menu category buttons on the right"
echo "  5. Click a food category (e.g., FAVORITES, SIDES, etc.) to see menu items"
echo "  6. Click on at least 2 different menu items to add them to the order"
echo "  7. Click 'SEND' or the equivalent button to send the order to the kitchen"
