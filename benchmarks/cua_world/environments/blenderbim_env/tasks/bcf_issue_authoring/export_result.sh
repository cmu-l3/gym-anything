#!/bin/bash
echo "=== Exporting bcf_issue_authoring result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/bcf_result.json"
ZIP_PATH="/home/ga/BIMProjects/coordination_issues.bcfzip"

# Read task start timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Write the export Python script to parse the BCF ZIP
cat > /tmp/export_bcf.py << PYEOF
import sys
import json
import os
import zipfile
import xml.etree.ElementTree as ET

bcf_path = "$ZIP_PATH"
task_start = float("$TASK_START")

result = {
    "file_exists": False,
    "file_mtime": 0.0,
    "task_start": task_start,
    "is_valid_zip": False,
    "has_bcf_version": False,
    "topics_found": 0,
    "best_topic": {
        "title": "",
        "assigned_to": "",
        "has_comment": False,
        "has_viewpoint": False,
        "has_snapshot": False
    },
    "error": None
}

def strip_ns(tag):
    return tag.split('}', 1)[-1] if '}' in tag else tag

if os.path.exists(bcf_path):
    result["file_exists"] = True
    result["file_mtime"] = os.path.getmtime(bcf_path)
    
    try:
        if zipfile.is_zipfile(bcf_path):
            result["is_valid_zip"] = True
            with zipfile.ZipFile(bcf_path, 'r') as zf:
                namelist = zf.namelist()
                
                # Check for bcf.version
                if any(name.endswith('bcf.version') for name in namelist):
                    result["has_bcf_version"] = True
                
                # Find topic directories (UUIDs)
                # A topic directory contains markup.bcf
                topic_dirs = set(os.path.dirname(name) for name in namelist if name.endswith('markup.bcf'))
                result["topics_found"] = len(topic_dirs)
                
                best_topic_score = -1
                
                for tdir in topic_dirs:
                    topic_data = {
                        "title": "",
                        "assigned_to": "",
                        "has_comment": False,
                        "has_viewpoint": False,
                        "has_snapshot": False
                    }
                    
                    # Parse markup.bcf
                    markup_path = f"{tdir}/markup.bcf" if tdir else "markup.bcf"
                    if markup_path in namelist:
                        try:
                            markup_content = zf.read(markup_path)
                            root = ET.fromstring(markup_content)
                            
                            # Find elements ignoring namespaces
                            for elem in root.iter():
                                tag = strip_ns(elem.tag)
                                if tag == "Title" and elem.text:
                                    topic_data["title"] = elem.text.strip()
                                elif tag == "AssignedTo" and elem.text:
                                    topic_data["assigned_to"] = elem.text.strip()
                                elif tag == "Comment":
                                    # Need to check if it's the wrapper <Comment> or the actual text node
                                    for sub in elem.iter():
                                        if strip_ns(sub.tag) == "Comment" and sub.text and sub.text.strip():
                                            topic_data["has_comment"] = True
                        except Exception as e:
                            pass
                    
                    # Check for viewpoint (.bcfv)
                    if any(name.startswith(f"{tdir}/") and name.endswith('.bcfv') for name in namelist):
                        topic_data["has_viewpoint"] = True
                        
                    # Check for snapshot (.png)
                    for name in namelist:
                        if name.startswith(f"{tdir}/") and name.endswith('.png'):
                            info = zf.getinfo(name)
                            if info.file_size > 0:
                                topic_data["has_snapshot"] = True
                                break
                    
                    # Score this topic to find the best match for our requirements
                    score = 0
                    if "clearance" in topic_data["title"].lower(): score += 3
                    if "architect@example.com" in topic_data["assigned_to"].lower(): score += 3
                    if topic_data["has_comment"]: score += 1
                    if topic_data["has_viewpoint"]: score += 2
                    if topic_data["has_snapshot"]: score += 2
                    
                    if score > best_topic_score:
                        best_topic_score = score
                        result["best_topic"] = topic_data
                        
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

python3 /tmp/export_bcf.py > "$RESULT_FILE"

echo "Export complete:"
cat "$RESULT_FILE"