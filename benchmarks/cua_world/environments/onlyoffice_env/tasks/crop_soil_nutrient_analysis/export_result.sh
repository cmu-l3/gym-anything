#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Crop Soil Nutrient Analysis Result ==="

# Capture final screenshot
su - ga -c "DISPLAY=:1 import -window root /tmp/crop_soil_nutrient_analysis_final_screenshot.png" 2>/dev/null || true

# Try to save the document cleanly if ONLYOFFICE is still running
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
fi

# Force kill if it didn't close
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi
sleep 1

OUTPUT_PATH="/home/ga/Documents/Spreadsheets/soil_crop_analysis.xlsx"
FILE_EXISTS="false"
FILE_SIZE=0

if [ -f "$OUTPUT_PATH" ]; then
    echo "Analysis workbook saved: $OUTPUT_PATH"
    ls -lh "$OUTPUT_PATH"
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo 0)
else
    echo "Analysis workbook not found: $OUTPUT_PATH"
    # Fallback: check if they saved it with a slightly different name
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
fi

# Export result to JSON for the verifier to consume
cat > /tmp/crop_soil_nutrient_analysis_result.json << JSONEOF
{
  "task_name": "crop_soil_nutrient_analysis",
  "timestamp": $(date +%s),
  "output_file_exists": $FILE_EXISTS,
  "output_file_size": $FILE_SIZE,
  "output_path": "$OUTPUT_PATH"
}
JSONEOF

echo "Result JSON saved to /tmp/crop_soil_nutrient_analysis_result.json"
echo "=== Export Complete ==="