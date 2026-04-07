#!/bin/bash
echo "=== Exporting grounded_coil_spring result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_PATH="/home/ga/Documents/SolveSpace/grounded_spring.slvs"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Try to export to OBJ and calculate bounds
OBJ_FILE="/tmp/model.obj"
rm -f "$OBJ_FILE"
if [ "$FILE_EXISTS" = "true" ]; then
    # Try solvespace-cli or solvespace for headless obj export
    if which solvespace-cli >/dev/null 2>&1; then
        solvespace-cli export-obj "$OBJ_FILE" "$FILE_PATH" 2>/dev/null || true
    else
        solvespace export-obj "$OBJ_FILE" "$FILE_PATH" 2>/dev/null || true
    fi
fi

# Pure python robust OBJ bounds parser
BOUNDS_JSON="{}"
if [ -f "$OBJ_FILE" ]; then
    BOUNDS_JSON=$(python3 -c "
import sys, json
bounds = {'x_min': 9999.0, 'x_max': -9999.0, 'y_min': 9999.0, 'y_max': -9999.0, 'z_min': 9999.0, 'z_max': -9999.0, 'success': False}
try:
    with open('$OBJ_FILE', 'r') as f:
        for line in f:
            if line.startswith('v '):
                parts = line.split()
                if len(parts) >= 4:
                    try:
                        x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
                        bounds['x_min'] = min(bounds['x_min'], x)
                        bounds['x_max'] = max(bounds['x_max'], x)
                        bounds['y_min'] = min(bounds['y_min'], y)
                        bounds['y_max'] = max(bounds['y_max'], y)
                        bounds['z_min'] = min(bounds['z_min'], z)
                        bounds['z_max'] = max(bounds['z_max'], z)
                    except ValueError:
                        pass
    if bounds['x_min'] != 9999.0:
        bounds['success'] = True
except Exception:
    pass
print(json.dumps(bounds))
" 2>/dev/null || echo '{"success": false}')
else
    BOUNDS_JSON='{"success": false}'
fi

# Check if SolveSpace is running
APP_RUNNING="false"
if is_solvespace_running; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "bounds": $BOUNDS_JSON
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="