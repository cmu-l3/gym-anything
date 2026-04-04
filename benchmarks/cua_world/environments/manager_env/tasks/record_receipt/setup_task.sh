#!/bin/bash
# Setup script for record_receipt task in Manager.io

echo "=== Setting up record_receipt task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

echo "$(date +%s)" > /tmp/manager_task_start_time

echo "Opening Manager.io Receipts module (New Receipt form)..."
open_manager_at "receipts" "new"

echo ""
echo "=== record_receipt task setup complete ==="
echo ""
echo "TASK: Record a customer payment (receipt) in Manager.io (Northwind Traders)"
echo ""
echo "Receipt details:"
echo "  Bank Account:   Cash on Hand"
echo "  Date:           Today"
echo "  Line item:"
echo "    Account:      Accounts Receivable (or customer receivable account)"
echo "    Customer:     Alfreds Futterkiste"
echo "    Amount:       440.00"
echo ""
echo "  (Leave Sales Invoice blank — no invoice linking required)"
echo ""
echo "Login: administrator / (empty password)"
