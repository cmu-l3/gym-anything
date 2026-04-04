#!/bin/bash
echo "=== Exporting reformat_and_export_dicom_series result ==="

source /workspace/scripts/task_utils.sh

# Configuration
OUTPUT_DIR="/home/ga/Documents/reoriented_dicom"
SOURCE_DIR="/home/ga/DICOM/ct_cranium"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create a python script to analyze the output directory
# We use python because bash string manipulation of binary files is flaky
cat > /tmp/analyze_dicom_output.py << 'PYEOF'
import os
import sys
import json
import hashlib

output_dir = sys.argv[1]
source_dir = sys.argv[2]
task_start_time = float(sys.argv[3])

result = {
    "output_dir_exists": False,
    "file_count": 0,
    "valid_dicom_count": 0,
    "files_created_during_task": False,
    "content_modified": False,
    "errors": []
}

def is_dicom(filepath):
    """Check for DICM magic at offset 128."""
    try:
        with open(filepath, 'rb') as f:
            f.seek(128)
            magic = f.read(4)
        return magic == b'DICM'
    except Exception:
        return False

def get_file_hash(filepath):
    h = hashlib.md5()
    try:
        with open(filepath, 'rb') as f:
            # Read first 1MB to be fast
            chunk = f.read(1024*1024) 
            h.update(chunk)
        return h.hexdigest()
    except:
        return None

if os.path.exists(output_dir) and os.path.isdir(output_dir):
    result["output_dir_exists"] = True
    
    # Recursively find files
    found_files = []
    for root, dirs, files in os.walk(output_dir):
        for f in files:
            found_files.append(os.path.join(root, f))
            
    result["file_count"] = len(found_files)
    
    if found_files:
        # Check timestamps
        new_files = 0
        valid_dicoms = 0
        
        for f in found_files:
            try:
                mtime = os.path.getmtime(f)
                if mtime > task_start_time:
                    new_files += 1
                if is_dicom(f):
                    valid_dicoms += 1
            except Exception as e:
                pass
                
        result["files_created_during_task"] = (new_files > 0)
        result["valid_dicom_count"] = valid_dicoms
        
        # Check content modification
        # If the user just copied files, hashes would match source
        # We sample a few source files and a few output files
        source_hashes = set()
        if os.path.exists(source_dir):
            for f in os.listdir(source_dir)[:20]: # Sample 20 source files
                full_p = os.path.join(source_dir, f)
                if os.path.isfile(full_p):
                    h = get_file_hash(full_p)
                    if h: source_hashes.add(h)
        
        # Check if output files are distinct from source
        # In a reorientation, practically ALL pixel data changes, so hashes should be unique
        matches = 0
        samples = 0
        for f in found_files[:20]: # Sample 20 output files
            samples += 1
            h = get_file_hash(f)
            if h and h in source_hashes:
                matches += 1
        
        # If we have 0 matches, content is modified
        if samples > 0 and matches == 0:
            result["content_modified"] = True
        elif samples > 0:
            result["errors"].append(f"Found {matches} output files identical to source files")

print(json.dumps(result))
PYEOF

# Run analysis
if [ -d "$OUTPUT_DIR" ]; then
    # Ensure ga user can read it (if created by app)
    # chmod -R a+r "$OUTPUT_DIR" 2>/dev/null || true
    python3 /tmp/analyze_dicom_output.py "$OUTPUT_DIR" "$SOURCE_DIR" "$TASK_START" > /tmp/task_result.json
else
    echo '{"output_dir_exists": false, "file_count": 0, "valid_dicom_count": 0, "files_created_during_task": false, "content_modified": false}' > /tmp/task_result.json
fi

# Add screenshot path
# We use jq if available, or simple python script to append
python3 -c "import json; d=json.load(open('/tmp/task_result.json')); d['screenshot_path']='/tmp/task_final.png'; print(json.dumps(d))" > /tmp/task_result_final.json
mv /tmp/task_result_final.json /tmp/task_result.json

cat /tmp/task_result.json
echo "=== Export complete ==="