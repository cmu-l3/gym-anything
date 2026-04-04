#!/bin/bash
# Setup script for create_purchase_invoice task in Manager.io

echo "=== Setting up create_purchase_invoice task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

echo "$(date +%s)" > /tmp/manager_task_start_time

echo "Opening Manager.io Purchase Invoices module (New Purchase Invoice form)..."
open_manager_at "purchase_invoices" "new"

echo ""
echo "=== create_purchase_invoice task setup complete ==="
echo ""
echo "TASK: Create a new purchase invoice in Manager.io (Northwind Traders)"
echo ""
echo "Invoice details:"
echo "  Supplier:       Exotic Liquids (or any existing Northwind supplier)"
echo "  Date:           Today"
echo "  Supplier ref:   SUP-2024-001"
echo "  Line item 1:    Office Supplies, Qty=1, Price=250.00"
echo "  Line item 2:    Shipping Boxes, Qty=100, Price=1.50"
echo ""
echo "Login: administrator / (empty password)"
