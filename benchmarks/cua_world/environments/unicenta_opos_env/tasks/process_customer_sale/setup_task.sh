#!/bin/bash
echo "=== Setting up process_customer_sale task ==="

# Source shared utilities (do NOT use set -euo pipefail — pattern #25)
source /workspace/scripts/task_utils.sh

# Record task start time
record_task_start /tmp/task_start_time.txt

# -----------------------------------------------------------------------
# Restore clean database state
# -----------------------------------------------------------------------
echo "Restoring clean database state..."
kill_unicenta
sleep 2

restore_database

# -----------------------------------------------------------------------
# Clean up any previous sale artifacts
# -----------------------------------------------------------------------
echo "Cleaning up previous task artifacts..."

# Record initial ticket count (for delta-based verification — pattern #32)
INITIAL_TICKET_COUNT=$(unicenta_query_value "SELECT COUNT(*) FROM tickets;" 2>/dev/null || echo "0")
echo "Initial ticket count: $INITIAL_TICKET_COUNT"
echo "$INITIAL_TICKET_COUNT" > /tmp/initial_ticket_count.txt

INITIAL_PAYMENT_COUNT=$(unicenta_query_value "SELECT COUNT(*) FROM payments;" 2>/dev/null || echo "0")
echo "Initial payment count: $INITIAL_PAYMENT_COUNT"
echo "$INITIAL_PAYMENT_COUNT" > /tmp/initial_payment_count.txt

# Verify required products exist in catalog
echo "Verifying required products exist..."
for code in "049000006346" "028400055680" "013000006040"; do
    PROD=$(unicenta_query_value "SELECT name FROM products WHERE code='$code';")
    if [ -n "$PROD" ]; then
        echo "  OK: $PROD ($code)"
    else
        echo "  WARNING: Product with code $code not found!"
    fi
done

# -----------------------------------------------------------------------
# Start uniCenta oPOS
# -----------------------------------------------------------------------
echo "Starting uniCenta oPOS..."
start_unicenta
sleep 5

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved"

# Verify uniCenta is running
if pgrep -f "unicentaopos.jar" > /dev/null 2>&1; then
    echo "uniCenta oPOS is running"
else
    echo "WARNING: uniCenta oPOS may not be running"
fi

echo "=== process_customer_sale task setup complete ==="
