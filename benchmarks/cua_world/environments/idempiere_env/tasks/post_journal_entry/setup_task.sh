#!/bin/bash
echo "=== Setting up post_journal_entry task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record initial GL journal count
CLIENT_ID=$(get_gardenworld_client_id)
INITIAL_JOURNAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM gl_journal WHERE ad_client_id=${CLIENT_ID:-11}" 2>/dev/null || echo "0")
echo "Initial GL journal count: $INITIAL_JOURNAL_COUNT"
rm -f /tmp/initial_journal_count.txt 2>/dev/null || true
echo "$INITIAL_JOURNAL_COUNT" > /tmp/initial_journal_count.txt
chmod 666 /tmp/initial_journal_count.txt 2>/dev/null || true

# 2. Show available GL accounts (advertising/expense and cash/bank accounts)
echo "--- Available GL accounts (expense accounts) ---"
EXPENSE_ACCOUNTS=$(idempiere_query "SELECT value, name FROM c_elementvalue WHERE ad_client_id=${CLIENT_ID:-11} AND isactive='Y' AND (name ILIKE '%Advertis%' OR name ILIKE '%Marketing%') ORDER BY value LIMIT 10" 2>/dev/null || echo "(query failed)")
echo "  Advertising/Marketing accounts: $EXPENSE_ACCOUNTS"

CASH_ACCOUNTS=$(idempiere_query "SELECT value, name FROM c_elementvalue WHERE ad_client_id=${CLIENT_ID:-11} AND isactive='Y' AND (name ILIKE '%Cash%' OR name ILIKE '%Checking%' OR name ILIKE '%Bank%') ORDER BY value LIMIT 10" 2>/dev/null || echo "(query failed)")
echo "  Cash/Bank accounts: $CASH_ACCOUNTS"

# 3. Ensure Firefox is running and navigate to iDempiere
echo "--- Navigating to iDempiere ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to iDempiere dashboard (handles ZK leave-page dialog automatically)
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/post_journal_entry_initial.png
echo "  Initial screenshot saved to /tmp/post_journal_entry_initial.png"

echo "=== post_journal_entry task setup complete ==="
echo "Task: Create and post GL Journal for 'Q1 Marketing Campaign - Digital Advertising' (USD 3500)"
echo "Navigation hint: Menu > Financial Management > Accounting > GL Journal > New Record"
