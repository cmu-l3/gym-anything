#!/bin/bash
set -e
echo "=== Exporting Safety Bulletin Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file
OUTPUT_FILE="/home/ga/Documents/Winter_Safety_Alert.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Python script to analyze the ODT structure deeply
python3 << PYEOF
import zipfile
import json
import os
import re
import sys

output_path = "$OUTPUT_FILE"
result = {
    "file_exists": False,
    "file_size": 0,
    "columns_detected": False,
    "image_present": False,
    "wrapping_enabled": False,
    "borders_detected": False,
    "bullet_points_detected": False,
    "content_match": False,
    "timestamp_valid": False
}

if os.path.exists(output_path):
    result["file_exists"] = True
    stat = os.stat(output_path)
    result["file_size"] = stat.st_size
    
    # Check timestamp
    task_start = $TASK_START
    if stat.st_mtime > task_start:
        result["timestamp_valid"] = True

    try:
        with zipfile.ZipFile(output_path, 'r') as zf:
            # Read content.xml
            content_xml = zf.read('content.xml').decode('utf-8', errors='replace')
            styles_xml = zf.read('styles.xml').decode('utf-8', errors='replace')
            
            # 1. Check for Columns
            # Look for <style:section-properties style:editable="false"><style:columns style:column-count="2" ...
            # Or just style:column-count="2"
            if 'style:column-count="2"' in content_xml or 'style:column-count="2"' in styles_xml:
                result["columns_detected"] = True
            
            # 2. Check for Images
            # Look for <draw:frame> or <draw:image>
            if '<draw:image' in content_xml:
                result["image_present"] = True
            
            # 3. Check for Text Wrapping
            # This is usually in the style properties for the graphic/frame
            # style:wrap="parallel", "dynamic", "left", "right" (not "none" or "run-through" if we want wrap, usually "parallel" is standard for wrap around)
            # We specifically want to avoid 'none' (inline) if possible, or verify 'parallel'/'dynamic' exists.
            # In ODF, style:wrap="parallel" means text flows around.
            if 'style:wrap="parallel"' in content_xml or 'style:wrap="dynamic"' in content_xml or 'style:wrap="optimal"' in content_xml:
                result["wrapping_enabled"] = True
            # Also check common styles.xml
            if 'style:wrap="parallel"' in styles_xml or 'style:wrap="dynamic"' in styles_xml:
                 result["wrapping_enabled"] = True

            # 4. Check for Borders
            # Look for fo:border in paragraph properties or graphic properties
            if 'fo:border' in content_xml or 'fo:border' in styles_xml:
                # Filter out border="none"
                if re.search(r'fo:border="[^n]', content_xml) or re.search(r'fo:border="[^n]', styles_xml):
                    result["borders_detected"] = True
            
            # 5. Check for Bullet Points
            # Look for text:list
            if '<text:list' in content_xml:
                result["bullet_points_detected"] = True
            
            # 6. Check Content
            # Simple check for a unique string from the draft
            if "Hydraulic failure" in content_xml or "hydraulic failure" in content_xml: # Checking text presence
                result["content_match"] = True

    except Exception as e:
        result["error"] = str(e)

# Save result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)

PYEOF

# 4. Move result to accessible location if needed (verifier reads from /tmp/task_result.json via copy_from_env)
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="