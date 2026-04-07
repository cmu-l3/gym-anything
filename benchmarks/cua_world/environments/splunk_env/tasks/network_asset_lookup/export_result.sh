#!/bin/bash
echo "=== Exporting network_asset_lookup result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Search for the CSV file in Splunk's lookup directories
echo "Searching for network_assets.csv..."
CSV_PATH=$(find /opt/splunk/etc/ -name "network_assets.csv" | head -n 1)
CSV_EXISTS="false"
CSV_MTIME="0"
CSV_HEADERS=""

if [ -n "$CSV_PATH" ] && [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    # Extract headers (removing carriage returns and quotes)
    CSV_HEADERS=$(head -n 1 "$CSV_PATH" | tr -d '\r' | tr -d '"')
    echo "Found CSV at: $CSV_PATH"
else
    echo "CSV not found."
fi

# 2. Query REST API for the Lookup Definition
echo "Querying Lookup Definition..."
DEF_TEMP=$(mktemp /tmp/lookup_def.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/data/transforms/lookups/network_asset_lookup?output_mode=json" \
    > "$DEF_TEMP" 2>/dev/null

# 3. Query REST API for Automatic Lookups
echo "Querying Automatic Lookups..."
AUTO_TEMP=$(mktemp /tmp/auto_lookups.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/data/props/lookups?output_mode=json&count=0" \
    > "$AUTO_TEMP" 2>/dev/null

# Parse the REST API responses using Python
ANALYSIS=$(python3 - "$DEF_TEMP" "$AUTO_TEMP" << 'PYEOF'
import sys, json

# Parse Lookup Definition
try:
    with open(sys.argv[1], 'r') as f:
        def_data = json.load(f)
except:
    def_data = {}

def_entry = def_data.get('entry', [])
def_exists = len(def_entry) > 0
def_filename = def_entry[0].get('content', {}).get('filename', '') if def_exists else ''

# Parse Automatic Lookups
try:
    with open(sys.argv[2], 'r') as f:
        auto_data = json.load(f)
except:
    auto_data = {}

auto_entry = auto_data.get('entry', [])
auto_exists = False
auto_name = ""
auto_content = {}
auto_stanza = ""

expected_auto_name = "asset_context_for_security"

for entry in auto_entry:
    name = entry.get('name', '')
    if expected_auto_name.lower() in name.lower():
        auto_exists = True
        auto_name = name
        auto_content = entry.get('content', {})
        
        # Splunk API structure sometimes exposes stanza directly, or it's embedded in the name
        auto_stanza = auto_content.get('stanza', '')
        if not auto_stanza and ":" in name:
            auto_stanza = name.split(":")[0].strip()
        break

result = {
    "lookup_def_exists": def_exists,
    "lookup_def_filename": def_filename,
    "auto_lookup_exists": auto_exists,
    "auto_lookup_name": auto_name,
    "auto_lookup_stanza": auto_stanza,
    "auto_lookup_content": auto_content
}
print(json.dumps(result))
PYEOF
)

rm -f "$DEF_TEMP" "$AUTO_TEMP"

# Read task start time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": ${TASK_START},
    "csv": {
        "exists": ${CSV_EXISTS},
        "path": "${CSV_PATH}",
        "mtime": ${CSV_MTIME},
        "headers": "${CSV_HEADERS}"
    },
    "api_analysis": ${ANALYSIS},
    "export_timestamp": "$(date +%s)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="