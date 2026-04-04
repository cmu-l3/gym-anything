#!/bin/bash
echo "=== Exporting Project Lifecycle Tracking Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define paths
PBIX_PATH="/home/ga/Desktop/Construction_Status.pbix"
RESULT_JSON="/tmp/task_result.json"

# Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if file exists
if [ -f "$PBIX_PATH" ]; then
    echo "Found .pbix file."
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$PBIX_PATH")
    
    # We need to analyze the PBIX content. PBIX is a zip file.
    # We will use a Python script to extract and parse the internal JSON models.
    
    cat << 'EOF' > /tmp/analyze_pbix.py
import zipfile
import json
import os
import sys
import shutil

pbix_path = "/home/ga/Desktop/Construction_Status.pbix"
temp_dir = "/tmp/pbix_extract"
result = {
    "file_exists": True,
    "file_size": 0,
    "has_sort_by_column": False,
    "sort_column_name": None,
    "measures": [],
    "visuals": [],
    "conditional_formatting": False
}

try:
    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)
    os.makedirs(temp_dir)

    result["file_size"] = os.path.getsize(pbix_path)

    with zipfile.ZipFile(pbix_path, 'r') as zip_ref:
        zip_ref.extractall(temp_dir)
    
    # 1. Parse DataModelSchema (The Data Model)
    # This file contains table and column definitions
    schema_path = os.path.join(temp_dir, "DataModelSchema")
    # Sometimes it has an extension or is in a subdir, but usually root in recent PBI
    # If not found, look recursively
    if not os.path.exists(schema_path):
        for root, dirs, files in os.walk(temp_dir):
            if "DataModelSchema" in files:
                schema_path = os.path.join(root, "DataModelSchema")
                break
    
    if os.path.exists(schema_path):
        with open(schema_path, 'r', encoding='utf-16-le') as f:
            schema = json.load(f)
        
        # Check tables
        model = schema.get("model", {})
        tables = model.get("tables", [])
        
        for table in tables:
            columns = table.get("columns", [])
            measures = table.get("measures", [])
            
            # Check for Measures
            for m in measures:
                result["measures"].append(m.get("name"))
            
            # Check for Sort By Column on 'Stage'
            for c in columns:
                if c.get("name") == "Stage":
                    # Check if 'sortByColumn' property is set
                    if "sortByColumn" in c:
                        result["has_sort_by_column"] = True
                        result["sort_column_name"] = c["sortByColumn"]

    # 2. Parse Report/Layout (The Visuals)
    layout_path = os.path.join(temp_dir, "Report", "Layout")
    if os.path.exists(layout_path):
        with open(layout_path, 'r', encoding='utf-16-le') as f:
            layout = json.load(f)
            
        sections = layout.get("sections", [])
        for section in sections:
            visualContainers = section.get("visualContainers", [])
            for vc in visualContainers:
                config_str = vc.get("config")
                if config_str:
                    config = json.loads(config_str)
                    
                    # Identify Visual Type
                    single_visual = config.get("singleVisual", {})
                    vis_type = single_visual.get("visualType")
                    if vis_type:
                        result["visuals"].append(vis_type)
                    
                    # Check Conditional Formatting
                    # It usually appears in objects -> property -> conditionalFormatting
                    # or in the visual config under 'vcObjects'
                    
                    # Deep search for "conditionalFormatting" key in config string
                    if "conditionalFormatting" in config_str:
                         result["conditional_formatting"] = True

except Exception as e:
    result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

    python3 /tmp/analyze_pbix.py

else
    echo "PBIX file not found."
    FILE_EXISTS="false"
    cat << EOF > /tmp/task_result.json
{
    "file_exists": false,
    "error": "File Construction_Status.pbix not found"
}
EOF
fi

# Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export Complete ==="