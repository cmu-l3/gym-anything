#!/bin/bash
set -e
echo "=== Exporting Mach Study Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Check Project File
PROJECT_FILE="/home/ga/Documents/projects/mach_study.wpa"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
HAS_NACA_0012="false"
HAS_MACH_0="false"
HAS_MACH_03="false"
HAS_MACH_05="false"
POLAR_COUNT=0
HAS_RE_3M="false"

if [ -f "$PROJECT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$PROJECT_FILE")
    FILE_MTIME=$(stat -c%Y "$PROJECT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # 3. Parse File Content
    # QBlade .wpa files are text-based (INI/XML style). We use grep to check content.
    # If binary, strings command would extract text.
    
    # Check for Airfoil Name
    if grep -qi "NACA.*0012" "$PROJECT_FILE" || grep -qi "NACA.*0012" "$PROJECT_FILE"; then
        HAS_NACA_0012="true"
    fi
    
    # Check for Mach numbers in Polar definitions
    # Note: Format usually contains "Mach = 0.300" or similar, or XML tags
    if grep -q "Mach.*0\." "$PROJECT_FILE" || grep -q "Ma.*=.*0\." "$PROJECT_FILE"; then
         # Check specific values (allowing for formatting variations like 0.3000)
         if grep -q "0\.3" "$PROJECT_FILE"; then HAS_MACH_03="true"; fi
         if grep -q "0\.5" "$PROJECT_FILE"; then HAS_MACH_05="true"; fi
         # Mach 0.0 might be represented as 0 or 0.000
         if grep -q "Mach.*=.*0" "$PROJECT_FILE" || grep -q "Ma.*=.*0" "$PROJECT_FILE"; then HAS_MACH_0="true"; fi
    fi

    # Check for Reynolds Number (3000000 or 3e6)
    if grep -q "3000000" "$PROJECT_FILE" || grep -q "3\.0.*6" "$PROJECT_FILE"; then
        HAS_RE_3M="true"
    fi

    # Count Polars (rough estimate by counting polar headers or definitions)
    # This depends on exact WPA format, but looking for distinct polar blocks is a good proxy
    POLAR_COUNT=$(grep -c -i "Polar" "$PROJECT_FILE" || echo "0")
fi

# 4. Check Application State
APP_RUNNING=$(is_qblade_running)

# 5. Create JSON Result
# Using python to write JSON safely
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'file_exists': $FILE_EXISTS,
    'file_path': '$PROJECT_FILE',
    'file_size_bytes': $FILE_SIZE,
    'created_during_task': $FILE_CREATED_DURING_TASK,
    'content_check': {
        'has_naca_0012': $HAS_NACA_0012,
        'has_mach_0': $HAS_MACH_0,
        'has_mach_03': $HAS_MACH_03,
        'has_mach_05': $HAS_MACH_05,
        'has_re_3m': $HAS_RE_3M,
        'estimated_polar_count': $POLAR_COUNT
    },
    'app_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# 6. Save result with permissions
mv /tmp/task_result.json /tmp/mach_study_result.json
chmod 666 /tmp/mach_study_result.json

echo "Result exported to /tmp/mach_study_result.json"
cat /tmp/mach_study_result.json
echo "=== Export complete ==="