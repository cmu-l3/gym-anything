#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up sequence_invoice_system task ==="
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running
wait_for_orientdb 120

# Clean up any previous attempts to ensure a clean state
echo "Cleaning up previous task artifacts..."

# Drop index first (if exists)
orientdb_sql "demodb" "DROP INDEX Invoices.InvoiceId IF EXISTS" >/dev/null 2>&1 || true
sleep 1

# Drop class
orientdb_sql "demodb" "DROP CLASS Invoices UNSAFE" >/dev/null 2>&1 || true
sleep 1

# Drop sequences
orientdb_sql "demodb" "DROP SEQUENCE invoiceIdSeq" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP SEQUENCE receiptSeq" >/dev/null 2>&1 || true
sleep 1

# Record initial Invoices count (should be 0 or class doesn't exist)
# We save "0" as the baseline
echo "0" > /tmp/initial_invoice_count.txt

# Launch Firefox to OrientDB Studio
# We use the utility function to handle clean launch
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Maximize and focus Firefox
sleep 3
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="