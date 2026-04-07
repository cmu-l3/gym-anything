#!/bin/bash
echo "=== Exporting compute_broadband_magnitudes_scamp results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/noto_reprocessed.scml"

# 1. Take final screenshot
take_screenshot /tmp/task_final_state.png ga

# 2. Check output file creation and timestamp
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Configuration Files for mB and Mwp
SCAMP_CONFIGS=$(cat /home/ga/seiscomp/etc/scamp.cfg /home/ga/.seiscomp/scamp.cfg 2>/dev/null | grep -v "^#" || true)
SCMAG_CONFIGS=$(cat /home/ga/seiscomp/etc/scmag.cfg /home/ga/.seiscomp/scmag.cfg 2>/dev/null | grep -v "^#" || true)

CONFIG_MB_ENABLED="false"
CONFIG_MWP_ENABLED="false"

if echo "$SCAMP_CONFIGS" | grep -q "mB" && echo "$SCMAG_CONFIGS" | grep -q "mB"; then
    CONFIG_MB_ENABLED="true"
fi
if echo "$SCAMP_CONFIGS" | grep -q "Mwp" && echo "$SCMAG_CONFIGS" | grep -q "Mwp"; then
    CONFIG_MWP_ENABLED="true"
fi

# 4. Extract Magnitudes from Output XML using Python
# (Parsing SeisComP XML with grep/awk is unreliable due to nesting and namespaces)
XML_PARSE_RESULT=$(python3 - << 'EOF'
import sys
import json
import xml.etree.ElementTree as ET

output_path = "/home/ga/Documents/noto_reprocessed.scml"
result = {"parsed_magnitudes": [], "error": None}

try:
    tree = ET.parse(output_path)
    root = tree.getroot()
    
    # Iterate through all elements to find magnitudes (ignoring namespace URIs)
    for elem in root.iter():
        if elem.tag.endswith('magnitude') and 'publicID' in elem.attrib:
            # We found a top-level or nested Magnitude object
            mag_type = None
            mag_val = None
            
            for child in elem:
                if child.tag.endswith('type'):
                    mag_type = child.text
                elif child.tag.endswith('magnitude'):
                    for val_child in child:
                        if val_child.tag.endswith('value'):
                            try:
                                mag_val = float(val_child.text)
                            except ValueError:
                                pass
            
            if mag_type and mag_val is not None:
                result["parsed_magnitudes"].append({"type": mag_type, "value": mag_val})
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF
)

# 5. Build Final JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "config_mb_enabled": $CONFIG_MB_ENABLED,
    "config_mwp_enabled": $CONFIG_MWP_ENABLED,
    "xml_extraction": $XML_PARSE_RESULT
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="