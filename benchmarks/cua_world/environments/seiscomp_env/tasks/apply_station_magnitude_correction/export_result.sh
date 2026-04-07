#!/bin/bash
echo "=== Exporting task results ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

export TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
export TASK_END=$(date +%s)

# Check all related key/binding files for the target station
export FILE_EXISTS="false"
export MODIFIED_DURING_TASK="false"
export FILE_CONTENT=""

KEY_FILES=$(ls $SEISCOMP_ROOT/etc/key/*GE_TOLI* 2>/dev/null)
for f in $KEY_FILES; do
    if [ -f "$f" ]; then
        FILE_EXISTS="true"
        MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            MODIFIED_DURING_TASK="true"
        fi
        FILE_CONTENT="$FILE_CONTENT\n--- $f ---\n$(cat $f)\n"
    fi
done

# Dump scmag effective configuration for the station
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH seiscomp exec scmag --dump-config > /tmp/scmag_dump.txt 2>/dev/null" || true
export DUMP_CONTENT=$(cat /tmp/scmag_dump.txt 2>/dev/null | grep -A 30 -i "TOLI" || echo "")

# Extract global configuration to ensure correction was not mistakenly applied globally
export GLOBAL_CONTENT=$(cat $SEISCOMP_ROOT/etc/global.cfg 2>/dev/null | grep -i "magnitude" || echo "")
export GLOBAL_SCMAG_CONTENT=$(cat $SEISCOMP_ROOT/etc/scmag.cfg 2>/dev/null | grep -i "magnitude" || echo "")

# Create JSON result using Python to safely handle multi-line strings
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, os
data = {
    'task_start': int(os.environ.get('TASK_START', 0)),
    'task_end': int(os.environ.get('TASK_END', 0)),
    'file_exists': os.environ.get('FILE_EXISTS') == 'true',
    'modified_during_task': os.environ.get('MODIFIED_DURING_TASK') == 'true',
    'file_content': os.environ.get('FILE_CONTENT', ''),
    'dump_content': os.environ.get('DUMP_CONTENT', ''),
    'global_content': os.environ.get('GLOBAL_CONTENT', ''),
    'global_scmag_content': os.environ.get('GLOBAL_SCMAG_CONTENT', '')
}
with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f)
"

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="