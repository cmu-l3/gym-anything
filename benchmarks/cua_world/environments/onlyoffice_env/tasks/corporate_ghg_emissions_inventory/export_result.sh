#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting GHG Emissions Inventory Result ==="

# Final screenshot
su - ga -c "DISPLAY=:1 import -window root /tmp/ghg_emissions_final_screenshot.png" || true

# Ensure work is saved
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
fi

if is_onlyoffice_running; then
    kill_onlyoffice ga
fi
sleep 1

REPORT_PATH="/home/ga/Documents/Spreadsheets/ghg_inventory_2023.xlsx"
OUTPUT_PATH="$REPORT_PATH"

# Allow fallback if the user saved it under a different name in the same folder
if [ -f "$REPORT_PATH" ]; then
    echo "GHG inventory saved: $REPORT_PATH"
else
    echo "GHG inventory not found at exact path. Checking alternatives..."
    ALT_PATH=$(ls -t /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null | head -1 || echo "")
    if [ -n "$ALT_PATH" ]; then
        echo "Found alternative file: $ALT_PATH"
        OUTPUT_PATH="$ALT_PATH"
    fi
fi

# Package state for the verifier
cat > /tmp/ghg_inventory_result.json << JSONEOF
{
  "task_name": "corporate_ghg_emissions_inventory",
  "timestamp": $(date +%s),
  "output_file_exists": $([ -f "$OUTPUT_PATH" ] && echo "true" || echo "false"),
  "output_file_size": $(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo 0),
  "output_path": "$OUTPUT_PATH"
}
JSONEOF

echo "=== Export Complete ==="