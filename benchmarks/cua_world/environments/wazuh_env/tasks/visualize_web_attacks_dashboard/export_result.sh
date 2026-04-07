#!/bin/bash
# export_result.sh for visualize_web_attacks_dashboard
set -e

echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Output file
RESULT_FILE="/tmp/task_result.json"

# ==============================================================================
# Fetch Saved Objects (Dashboards and Visualizations)
# ==============================================================================

# Credentials for Wazuh Dashboard (OpenSearch Dashboards)
# Using the internal user 'wazuh-wui' and password defined in setup_wazuh.sh
DASHBOARD_USER="wazuh-wui"
DASHBOARD_PASS="MyS3cr37P450r.*-"
API_BASE="https://localhost/api/saved_objects"

# 1. Search for the Dashboard
echo "Fetching dashboard..."
DASHBOARD_JSON=$(curl -sk -u "${DASHBOARD_USER}:${DASHBOARD_PASS}" \
    "${API_BASE}/_find?type=dashboard&search_fields=title&search=Web_Attack_Analysis")

# 2. Fetch all Visualizations created by the user (fetching latest 50 to be safe)
echo "Fetching visualizations..."
VIZ_JSON=$(curl -sk -u "${DASHBOARD_USER}:${DASHBOARD_PASS}" \
    "${API_BASE}/_find?type=visualization&per_page=50&sort_field=updated_at&sort_order=desc")

# 3. Combine into a single JSON for the verifier
# We use Python to merge them cleanly to avoid messy bash JSON manipulation
python3 -c "
import json
import sys

try:
    dashboard_data = json.loads('''$DASHBOARD_JSON''')
    viz_data = json.loads('''$VIZ_JSON''')
    
    result = {
        'dashboard_objects': dashboard_data.get('saved_objects', []),
        'visualization_objects': viz_data.get('saved_objects', []),
        'screenshot_path': '/tmp/task_final.png',
        'timestamp': '$(date +%s)'
    }
    
    with open('$RESULT_FILE', 'w') as f:
        json.dump(result, f, indent=2)
        
    print(f'Successfully exported {len(result[\"dashboard_objects\"])} dashboards and {len(result[\"visualization_objects\"])} visualizations.')
except Exception as e:
    print(f'Error processing JSON: {e}')
    # Write minimal error json
    with open('$RESULT_FILE', 'w') as f:
        json.dump({'error': str(e)}, f)
"

# Handle permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export Complete ==="
cat "$RESULT_FILE"