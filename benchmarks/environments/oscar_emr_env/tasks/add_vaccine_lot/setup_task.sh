#!/bin/bash
# Setup script for Add Vaccine Lot task
# Ensures clean state by removing the target lot if it exists

echo "=== Setting up Add Vaccine Lot Task ==="

source /workspace/scripts/task_utils.sh

# Target data
LOT_NUMBER="FL2025-X9"

# 1. Clean up: Delete the lot if it already exists to ensure the agent actually creates it
echo "Cleaning up any existing records for lot $LOT_NUMBER..."
# OSCAR typically stores lots in 'prevention_lot'
oscar_query "DELETE FROM prevention_lot WHERE lot_number='$LOT_NUMBER'" 2>/dev/null || true
# Also check 'immunization_lot' just in case of schema variations
oscar_query "DELETE FROM immunization_lot WHERE lot_number='$LOT_NUMBER'" 2>/dev/null || true

# 2. Record Task Start Time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Record initial count of lots (for comparison)
INITIAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM prevention_lot" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_lot_count.txt

# 4. Ensure Firefox is open on OSCAR login
ensure_firefox_on_oscar

# 5. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target Lot: $LOT_NUMBER"
echo "Target Expiry: 2026-12-31"