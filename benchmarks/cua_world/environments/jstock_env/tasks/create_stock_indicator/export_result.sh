#!/bin/bash
echo "=== Exporting Create Stock Indicator Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ============================================================
# Check for new indicator files
# ============================================================
echo "Searching for new indicator files..."

# Find files in .jstock directory modified after task start
# Excluding log files and temporary artifacts
NEW_FILES=$(find /home/ga/.jstock -type f -newermt "@$TASK_START" ! -name "*.log" ! -name "*.lock" 2>/dev/null)

FILE_FOUND="false"
INDICATOR_NAME_FOUND="false"
PRICE_COND_FOUND="false"
VOLUME_COND_FOUND="false"
AND_LOGIC_FOUND="false"
MATCHING_FILE=""

if [ -n "$NEW_FILES" ]; then
    echo "New files detected:"
    echo "$NEW_FILES"
    
    # Iterate through new files to check content
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            # Check for Indicator Name "HighMomentum"
            if grep -qi "HighMomentum" "$file"; then
                FILE_FOUND="true"
                INDICATOR_NAME_FOUND="true"
                MATCHING_FILE="$file"
                
                # Check for Price Condition (100 or 100.0)
                # XML often stores it like <value>100.0</value> or attribute value="100.0"
                if grep -q "100" "$file"; then
                    PRICE_COND_FOUND="true"
                fi
                
                # Check for Volume Condition (1000000)
                if grep -q "1000000" "$file"; then
                    VOLUME_COND_FOUND="true"
                fi
                
                # Check for AND logic
                # JStock often uses "AndOperator" or similar in XML
                # Or if both conditions are present in one valid XML, it implies logical composition
                if grep -qi "And" "$file" || grep -qi "Operator" "$file"; then
                    AND_LOGIC_FOUND="true"
                elif [ "$PRICE_COND_FOUND" = "true" ] && [ "$VOLUME_COND_FOUND" = "true" ]; then
                    # Implicit AND if both conditions exist in the module file
                    AND_LOGIC_FOUND="true"
                fi
                
                break # Stop after finding the primary indicator file
            fi
        fi
    done <<< "$NEW_FILES"
else
    echo "No new files found."
fi

# Check if JStock is still running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_created_during_task": $FILE_FOUND,
    "indicator_name_found": $INDICATOR_NAME_FOUND,
    "price_condition_found": $PRICE_COND_FOUND,
    "volume_condition_found": $VOLUME_COND_FOUND,
    "logic_found": $AND_LOGIC_FOUND,
    "matching_file_path": "$MATCHING_FILE",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="