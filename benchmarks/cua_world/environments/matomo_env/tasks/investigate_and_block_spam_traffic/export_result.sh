#!/bin/bash
# Export script for Spam Investigation Task

echo "=== Exporting Results ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Query the configuration for Site 1
# We need excluded_ips, excluded_referrers, excluded_user_agents
SITE_CONFIG=$(matomo_query "SELECT excluded_ips, excluded_referrers, excluded_user_agents FROM matomo_site WHERE idsite=1")

# Use Python to safely parse/escape the output into JSON
# (Bash string handling with newlines/special chars can be tricky)
python3 -c "
import json
import sys

try:
    raw_data = sys.stdin.read().strip()
    if not raw_data:
        data = {'ips': '', 'refs': '', 'uas': ''}
    else:
        # data might come in tab-separated if using mysql -N -B, 
        # but exclusion fields usually don't contain tabs.
        parts = raw_data.split('\t')
        if len(parts) >= 3:
            data = {
                'ips': parts[0], 
                'refs': parts[1], 
                'uas': parts[2]
            }
        else:
            data = {'ips': '', 'refs': '', 'uas': '', 'error': 'parsing_mismatch'}

    # Add timestamp
    data['timestamp'] = '$(date +%s)'
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f, indent=2)
        
except Exception as e:
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)

" <<< "$SITE_CONFIG"

echo "Exported configuration:"
cat /tmp/task_result.json
echo "=== Export Complete ==="