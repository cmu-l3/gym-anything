#!/bin/bash
# Setup script for configure_invoice_defaults task
# Prepares Manager.io and navigates to the Sales Invoices list

echo "=== Setting up configure_invoice_defaults task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Manager.io is running and accessible
wait_for_manager 60

# 2. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Open Firefox at Manager.io
# We want to start at the Sales Invoices list to test if the agent can find "Form Defaults"
# (which is often a button at the bottom of the list or in settings)
echo "Opening Manager.io Sales Invoices module..."
open_manager_at "sales_invoices"

# 4. Wait for Firefox to settle and maximize
sleep 5
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Configure Form Defaults for Sales Invoices"
echo "Target Settings:"
echo " - Title: TAX INVOICE"
echo " - Due Date: Net 14 days"
echo " - Notes: Payment is due within 14 days. Please include invoice number in transfer reference."