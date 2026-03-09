#!/bin/bash
# Export script for Optimize Product SEO task

echo "=== Exporting Optimize Product SEO Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Load Initial State
if [ -f /tmp/initial_seo_state.json ]; then
    # We use python to parse the JSON robustly
    P1_ID=$(python3 -c "import json; print(json.load(open('/tmp/initial_seo_state.json'))['p1']['id'])")
    P2_ID=$(python3 -c "import json; print(json.load(open('/tmp/initial_seo_state.json'))['p2']['id'])")
else
    echo "ERROR: Initial state file not found. Anti-gaming checks may fail."
    P1_ID=""
    P2_ID=""
fi

# Function to get current SEO data
get_seo_data() {
    local pid=$1
    if [ -z "$pid" ]; then return; fi
    
    # We query post_name (slug) and post_excerpt (short description) directly
    local query="SELECT post_name, post_excerpt FROM wp_posts WHERE ID=$pid"
    
    # Use python connector if available for better escaping, or careful bash
    # Here using the helper function but capturing fields carefully
    docker exec woocommerce-mariadb mysql -u wordpress -pwordpresspass wordpress -N -B -e "$query"
}

# Collect Final Data
echo "Collecting final product data..."

# Product 1 Data
P1_CURRENT_RAW=$(get_seo_data "$P1_ID")
P1_SLUG=$(echo "$P1_CURRENT_RAW" | cut -f1)
P1_EXCERPT=$(echo "$P1_CURRENT_RAW" | cut -f2)

# Product 2 Data
P2_CURRENT_RAW=$(get_seo_data "$P2_ID")
P2_SLUG=$(echo "$P2_CURRENT_RAW" | cut -f1)
P2_EXCERPT=$(echo "$P2_CURRENT_RAW" | cut -f2)

# Construct JSON result
# using jq if available or python for safe JSON creation
cat > /tmp/seo_result_script.py << PYEOF
import json
import os
import sys

# Read initial state
try:
    with open('/tmp/initial_seo_state.json', 'r') as f:
        initial = json.load(f)
except:
    initial = {"p1": {}, "p2": {}}

result = {
    "p1": {
        "id": "$P1_ID",
        "current_slug": """$(python3 -c "import sys, json; print(json.dumps(sys.argv[1]))" "$P1_SLUG")""",
        "current_excerpt": """$(python3 -c "import sys, json; print(json.dumps(sys.argv[1]))" "$P1_EXCERPT")""",
        "initial_slug": initial['p1'].get('initial_slug', ''),
        "initial_excerpt": initial['p1'].get('initial_excerpt', '')
    },
    "p2": {
        "id": "$P2_ID",
        "current_slug": """$(python3 -c "import sys, json; print(json.dumps(sys.argv[1]))" "$P2_SLUG")""",
        "current_excerpt": """$(python3 -c "import sys, json; print(json.dumps(sys.argv[1]))" "$P2_EXCERPT")""",
        "initial_slug": initial['p2'].get('initial_slug', ''),
        "initial_excerpt": initial['p2'].get('initial_excerpt', '')
    },
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

python3 /tmp/seo_result_script.py
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="