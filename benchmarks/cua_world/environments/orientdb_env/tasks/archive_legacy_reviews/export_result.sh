#!/bin/bash
echo "=== Exporting Archive Legacy Reviews Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare the result JSON
# We combine the initial state (recorded in setup) with basic task metadata.
# The heavy logic happens in the python verifier which queries the API.

INITIAL_STATE_FILE="/tmp/initial_db_state.json"
RESULT_FILE="/tmp/task_result.json"

if [ -f "$INITIAL_STATE_FILE" ]; then
    # Merge initial state into result
    cat "$INITIAL_STATE_FILE" > "$RESULT_FILE"
else
    echo '{"legacy_count": 0, "modern_count": 0, "error": "Initial state missing"}' > "$RESULT_FILE"
fi

# Add screenshot path to result (using jq if available, else simple append won't work well for json)
# We'll just use python to update the json safely
python3 -c "
import json
import os

try:
    with open('$RESULT_FILE', 'r') as f:
        data = json.load(f)
except Exception:
    data = {}

data['screenshot_path'] = '/tmp/task_final.png'
data['task_end_time'] = '$(date -Iseconds)'

with open('$RESULT_FILE', 'w') as f:
    json.dump(data, f, indent=4)
"

# Set permissions so the host can read it
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="