#!/bin/bash
# Setup script for create_customer task in Manager.io
# Navigates Firefox to the Customers > New Customer form in the Northwind business.

echo "=== Setting up create_customer task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager.io is running
wait_for_manager 60

# Record initial state
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/manager_task_start_time
echo "Task start time: $(date)"

# Open Firefox and navigate to Customers > New Customer
echo "Opening Manager.io Customers module (New Customer form)..."
open_manager_at "customers" "new"

echo ""
echo "=== create_customer task setup complete ==="
echo ""
echo "TASK: Create a new customer in Manager.io (Northwind Traders business)"
echo ""
echo "Customer details to enter:"
echo "  Name:            Blue River Technologies"
echo "  Code:            BRT-001"
echo "  Credit Limit:    25000"
echo "  Billing Address: 1847 Innovation Drive, Austin, TX 78701, United States"
echo "  Email:           accounts@blueriver.tech"
echo ""
echo "Login credentials: administrator / (empty password)"
