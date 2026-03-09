#!/bin/bash
# Setup script for add_inventory_item task in Manager.io

echo "=== Setting up add_inventory_item task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

echo "$(date +%s)" > /tmp/manager_task_start_time

echo "Opening Manager.io Inventory Items module (New Item form)..."
open_manager_at "inventory" "new"

echo ""
echo "=== add_inventory_item task setup complete ==="
echo ""
echo "TASK: Add a new inventory item in Manager.io (Northwind Traders)"
echo ""
echo "Item details:"
echo "  Name:           Artisan Roasted Coffee Blend"
echo "  Code:           ARB-001"
echo "  Unit:           kg"
echo "  Sales Price:    24.99"
echo "  Purchase Price: 12.00"
echo "  Description:    Premium single-origin Arabica coffee, slow-roasted in small batches"
echo ""
echo "Login: administrator / (empty password)"
