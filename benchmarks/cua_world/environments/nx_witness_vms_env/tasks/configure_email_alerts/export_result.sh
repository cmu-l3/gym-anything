#!/bin/bash
echo "=== Exporting configure_email_alerts results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Refresh token just in case agent messed it up (we need it to verify)
# If agent changed admin password, this might fail, but that would be a failed task anyway.
refresh_nx_token > /dev/null 2>&1 || true

# Query current system settings
echo "Querying system settings..."
SETTINGS_JSON=$(nx_api_get "/rest/v1/system/settings" 2>/dev/null || echo "{}")

# Extract relevant fields using Python
# We map the JSON response to a clean result object
python3 -c "
import sys, json, time

try:
    # Load settings from stdin
    data = json.load(sys.stdin)
    
    # Define interesting keys
    keys = ['smtpHost', 'smtpPort', 'smtpConnectionType', 'emailFrom', 'smtpUser', 'smtpPassword']
    
    # Extract values safely
    result = {k: data.get(k) for k in keys}
    
    # Add metadata
    result['task_start'] = $TASK_START
    result['task_end'] = $TASK_END
    result['timestamp'] = time.time()
    
    # Write to file
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
    print('Exported settings successfully.')
    
except Exception as e:
    print(f'Error processing settings: {e}')
    # Write failure state
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)

" <<< "$SETTINGS_JSON"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Set permissions so host can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json