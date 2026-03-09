#!/bin/bash
set -e
echo "=== Setting up rename_tables_columns task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Calculate hash of original ODB script to detect "no changes" later
echo "Calculating original script hash..."
python3 -c "
import zipfile, hashlib, sys
try:
    with zipfile.ZipFile('/home/ga/chinook.odb', 'r') as z:
        script = z.read('database/script')
        print(hashlib.sha256(script).hexdigest())
except Exception as e:
    print('ERROR')
" > /tmp/original_script_hash.txt

# Full setup sequence:
# 1. Kill existing LO instances
# 2. Restore fresh chinook.odb
# 3. Launch LO Base
# 4. Wait for window
# 5. Dismiss dialogs
# 6. Maximize window
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot for evidence
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

# Verify setup was successful
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
else
    echo "WARNING: Failed to capture initial screenshot."
fi

echo "=== Task setup complete ==="