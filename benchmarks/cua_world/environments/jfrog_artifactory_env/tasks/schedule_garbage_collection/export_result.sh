#!/bin/bash
echo "=== Exporting schedule_garbage_collection results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get the final system configuration via API
echo "Fetching final system configuration..."
FINAL_CONFIG_XML=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration")

# 3. Extract the GC Cron Expression using Python
# We write the XML to a file first to avoid quoting issues
echo "$FINAL_CONFIG_XML" > /tmp/final_config.xml

FINAL_CRON=$(python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('/tmp/final_config.xml')
    root = tree.getroot()
    # Artifactory config XML usually looks like:
    # <config>
    #   <garbageCollector>
    #     <cronExp>0 0 0 * * ?</cronExp>
    #   </garbageCollector>
    # ...
    # Namespace might be present, e.g. {http://artifactory.jfrog.org/xsd/3.1.2}config
    # We'll use a wildcard search or strip namespaces
    cron = None
    for elem in root.iter():
        if 'cronExp' in elem.tag and 'garbageCollector' in variable_parent_map(root, elem):
             cron = elem.text
             break
    
    # Simpler approach: direct find
    if not cron:
        # iterate all to find tag ending in cronExp
        for elem in root.iter():
            if elem.tag.endswith('cronExp'):
                # rough check parent
                cron = elem.text
                break
    
    print(cron if cron else 'NOT_FOUND')

# Helper to find parent (inefficient but works for small config)
def variable_parent_map(root, target):
    return 'garbageCollector' # Mock for the simplified snippet above
except Exception as e:
    print('ERROR')
" 2>/dev/null || echo "ERROR")

# Re-run python extraction with a more robust script embedded
cat > /tmp/extract_cron.py << 'EOF'
import sys
import xml.etree.ElementTree as ET

try:
    tree = ET.parse('/tmp/final_config.xml')
    root = tree.getroot()
    
    # Remove namespaces for easier finding
    for elem in root.iter():
        if '}' in elem.tag:
            elem.tag = elem.tag.split('}', 1)[1]
            
    gc = root.find('garbageCollector')
    if gc is not None:
        cron = gc.find('cronExp')
        if cron is not None:
            print(cron.text)
            sys.exit(0)
    
    print("NOT_FOUND")
except Exception as e:
    print(f"ERROR: {e}")
EOF

FINAL_CRON=$(python3 /tmp/extract_cron.py)
INITIAL_CRON=$(cat /tmp/initial_gc_cron.txt 2>/dev/null || echo "UNKNOWN")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Initial Cron: $INITIAL_CRON"
echo "Final Cron:   $FINAL_CRON"

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_cron": "$INITIAL_CRON",
    "final_cron": "$FINAL_CRON",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"