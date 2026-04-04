#!/bin/bash
# Setup script for create_sales_invoice task in Manager.io

echo "=== Setting up create_sales_invoice task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

echo "$(date +%s)" > /tmp/manager_task_start_time

echo "Opening Manager.io Sales Invoices module (New Sales Invoice form)..."
open_manager_at "sales_invoices" "new"

echo ""
echo "=== create_sales_invoice task setup complete ==="
echo ""
echo "TASK: Create a new sales invoice in Manager.io (Northwind Traders)"
echo ""
echo "Invoice details:"
echo "  Customer:  Alfreds Futterkiste (existing customer)"
echo "  Date:      Today's date"
echo "  Due Date:  30 days from today"
echo ""
echo "  Line item 1:"
echo "    Description: Consulting Services Q1"
echo "    Account:     Sales (or the income account in the dropdown)"
echo "    Qty:         10"
echo "    Unit Price:  150.00"
echo ""
echo "  Line item 2:"
echo "    Description: Software Support Retainer"
echo "    Account:     Sales"
echo "    Qty:         1"
echo "    Unit Price:  500.00"
echo ""
echo "  (Leave the Item field blank if present — fill Description and Account instead)"
echo ""
echo "Login: administrator / (empty password)"
