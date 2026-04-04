#!/bin/bash
# Setup script for view_balance_sheet task in Manager.io

echo "=== Setting up view_balance_sheet task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

echo "$(date +%s)" > /tmp/manager_task_start_time

echo "Opening Manager.io Reports module..."
open_manager_at "reports"

echo ""
echo "=== view_balance_sheet task setup complete ==="
echo ""
echo "TASK: View the Balance Sheet report in Manager.io (Northwind Traders)"
echo ""
echo "Steps:"
echo "  1. In the Reports section, find and click 'Balance Sheet'"
echo "  2. Set the date to the end of the current month (or latest available)"
echo "  3. Read Total Assets, Total Liabilities, and Total Equity"
echo "  4. Report the figures shown on screen"
echo ""
echo "Login: administrator / (empty password)"
