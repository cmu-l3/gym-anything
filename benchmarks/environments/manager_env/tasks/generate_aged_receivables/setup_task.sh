#!/bin/bash
# Setup script for generate_aged_receivables task in Manager.io

echo "=== Setting up generate_aged_receivables task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

echo "$(date +%s)" > /tmp/manager_task_start_time

echo "Opening Manager.io Reports module..."
open_manager_at "reports"

echo ""
echo "=== generate_aged_receivables task setup complete ==="
echo ""
echo "TASK: View the Aged Receivables report in Manager.io (Northwind Traders)"
echo ""
echo "Steps:"
echo "  1. In Reports section, find and click 'Aged Receivables'"
echo "  2. Set the report date to today"
echo "  3. Identify the customer with the largest outstanding balance"
echo "  4. Note the total outstanding accounts receivable"
echo "  5. Report both values"
echo ""
echo "Login: administrator / (empty password)"
