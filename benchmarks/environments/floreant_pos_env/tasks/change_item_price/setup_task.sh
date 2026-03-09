#!/bin/bash
# pre_task hook for change_item_price task
# Restores clean DB (so HAMMER COFFEE has its default price), then opens Floreant POS

echo "=== Setting up change_item_price task ==="

source /workspace/scripts/task_utils.sh

# Restore a clean database to ensure HAMMER COFFEE is at its default price ($2.00)
kill_floreant
sleep 1
echo "Restoring clean database snapshot..."
DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -n "$DB_POSDB" ] && [ -d /opt/floreantpos/posdb_backup ]; then
    rm -rf "$DB_POSDB"
    cp -r /opt/floreantpos/posdb_backup "$DB_POSDB"
    chown -R ga:ga "$DB_POSDB"
    echo "Database restored from backup (HAMMER COFFEE at default \$2.00)."
elif [ -d /opt/floreantpos/derby_server_backup ]; then
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Derby server restored from backup."
else
    echo "WARNING: No database backup found; proceeding without restore."
fi

# Start Floreant POS and log in
start_and_login

sleep 3

# Take initial screenshot
take_screenshot /tmp/floreant_task_start.png
echo "Initial state screenshot saved"

echo "=== change_item_price task setup complete ==="
echo ""
echo "Task: Change the price of 'HAMMER COFFEE' from \$2.00 to \$3.50"
echo "Steps:"
echo "  1. Click the 'BACK OFFICE' button on the terminal screen"
echo "  2. In the PIN dialog, click 1, 1, 1, 1 on the numeric keypad, then click OK"
echo "  3. Navigate to Explorers → Menu Items"
echo "  4. Find and select the 'HAMMER COFFEE' item from the list (search 'COFFEE' or scroll)"
echo "  5. Click the 'Edit' button at the bottom"
echo "  6. When the 'ENTER SECRET KEY' dialog appears, click OK (leave field empty)"
echo "  7. In the Edit dialog, clear the 'Unit Price (Excluding Tax)' field and enter: 3.50"
echo "  8. Click OK to save"
