#!/bin/bash
# Setup script for create_supplier task in Manager.io

echo "=== Setting up create_supplier task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

echo "$(date +%s)" > /tmp/manager_task_start_time

echo "Opening Manager.io Suppliers module (New Supplier form)..."
open_manager_at "suppliers" "new"

echo ""
echo "=== create_supplier task setup complete ==="
echo ""
echo "TASK: Create a new supplier in Manager.io (Northwind Traders)"
echo ""
echo "Supplier details:"
echo "  Name:            Pacific Import Supplies Ltd"
echo "  Code:            PIS-001"
echo "  Billing Address: 320 Harbor Blvd, San Francisco, CA 94105, United States"
echo "  Email:           purchasing@pacificimports.com"
echo ""
echo "Login: administrator / (empty password)"
