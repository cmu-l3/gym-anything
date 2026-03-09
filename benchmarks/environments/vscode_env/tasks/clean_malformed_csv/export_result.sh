#!/bin/bash
# set -euo pipefail

echo "=== Exporting Clean Malformed CSV Result ==="

WORKSPACE_DIR="/home/ga/workspace/data_cleanup"

# Give any running Python script time to complete
sleep 2

# Export the cleaned CSV if it exists
if [ -f "$WORKSPACE_DIR/customer_export_clean.csv" ]; then
    echo "Copying cleaned CSV..."
    cp "$WORKSPACE_DIR/customer_export_clean.csv" /tmp/customer_export_clean.csv 2>&1 || echo "" > /tmp/customer_export_clean.csv
else
    echo "⚠️ Cleaned CSV not found"
    echo "" > /tmp/customer_export_clean.csv
fi

# Export the Python script
if [ -f "$WORKSPACE_DIR/clean_data.py" ]; then
    echo "Copying Python script..."
    cp "$WORKSPACE_DIR/clean_data.py" /tmp/clean_data.py 2>&1 || echo "" > /tmp/clean_data.py
else
    echo "⚠️ Python script not found"
    echo "" > /tmp/clean_data.py
fi

# Export input CSV for verification reference
if [ -f "$WORKSPACE_DIR/customer_export_broken.csv" ]; then
    echo "Copying input CSV for reference..."
    cp "$WORKSPACE_DIR/customer_export_broken.csv" /tmp/customer_export_broken.csv 2>&1
fi

# Capture terminal history if available
if [ -f "/home/ga/.bash_history" ]; then
    tail -50 /home/ga/.bash_history > /tmp/bash_history.txt 2>&1 || echo "" > /tmp/bash_history.txt
fi

echo "✅ Export complete"
echo "Output file: $WORKSPACE_DIR/customer_export_clean.csv"
echo "Script file: $WORKSPACE_DIR/clean_data.py"