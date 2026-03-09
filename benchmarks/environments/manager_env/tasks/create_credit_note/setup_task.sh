#!/bin/bash
# Setup script for create_credit_note task in Manager.io

echo "=== Setting up create_credit_note task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

echo "$(date +%s)" > /tmp/manager_task_start_time

echo "Opening Manager.io Credit Notes module (New Credit Note form)..."
open_manager_at "credit_notes" "new"

echo ""
echo "=== create_credit_note task setup complete ==="
echo ""
echo "TASK: Create a sales credit note in Manager.io (Northwind Traders)"
echo ""
echo "Credit Note details:"
echo "  Customer:   Ernst Handel (existing Northwind customer)"
echo "  Date:       Today"
echo "  Reference:  CN-2024-001"
echo "  Line item:  Returned Beverages — Damaged Shipment, Qty=5, Price=18.00"
echo "  Total:      90.00"
echo ""
echo "Login: administrator / (empty password)"
