#!/bin/bash
echo "=== Exporting Save Scene Bundle Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Define paths
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_FILE="$EXPORTS_DIR/annotated_brain_scene.mrb"

# Initialize result variables
MRB_EXISTS="false"
MRB_SIZE_BYTES=0
MRB_MTIME=0
FILE_CREATED_DURING_TASK="false"
IS_VALID_ZIP="false"
CONTAINS_MRML="false"
MRML_FILENAME=""
VOLUME_DATA_BUNDLED="false"
NUM_FIDUCIALS=0
FIDUCIAL_LABELS='[]'
FIDUCIAL_COORDINATES='[]'
SLICER_RUNNING="false"

# Check if Slicer is running
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# Check for output file
if [ -f "$OUTPUT_FILE" ]; then
    MRB_EXISTS="true"
    MRB_SIZE_BYTES=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    MRB_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    echo "MRB file found: $OUTPUT_FILE"
    echo "Size: $MRB_SIZE_BYTES bytes"
    echo "Modified: $MRB_MTIME"
    
    # Check if file was created during task
    if [ "$MRB_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "File was created during task"
    else
        echo "WARNING: File existed before task started"
    fi
    
    # Try to extract and analyze MRB (it's a ZIP archive)
    EXTRACT_DIR="/tmp/mrb_extract_$$"
    mkdir -p "$EXTRACT_DIR"
    
    # Test if it's a valid ZIP
    if unzip -t "$OUTPUT_FILE" > /dev/null 2>&1; then
        IS_VALID_ZIP="true"
        echo "MRB is a valid ZIP archive"
        
        # Extract contents
        unzip -q -o "$OUTPUT_FILE" -d "$EXTRACT_DIR" 2>/dev/null || true
        
        # List contents
        echo "MRB contents:"
        ls -la "$EXTRACT_DIR" 2>/dev/null || true
        
        # Find MRML file
        MRML_FILE=$(find "$EXTRACT_DIR" -name "*.mrml" -type f 2>/dev/null | head -1)
        if [ -n "$MRML_FILE" ] && [ -f "$MRML_FILE" ]; then
            CONTAINS_MRML="true"
            MRML_FILENAME=$(basename "$MRML_FILE")
            echo "Found MRML scene file: $MRML_FILENAME"
            
            # Parse MRML for fiducials and volume
            python3 << PYEOF
import os
import sys
import json
import xml.etree.ElementTree as ET

mrml_path = "$MRML_FILE"
extract_dir = "$EXTRACT_DIR"

try:
    tree = ET.parse(mrml_path)
    root = tree.getroot()
    
    result = {
        "volume_found": False,
        "volume_data_file": None,
        "fiducials": [],
        "fiducial_nodes": 0
    }
    
    # Look for volume nodes
    for elem in root.iter():
        tag = elem.tag.lower() if elem.tag else ""
        attrib = {k.lower(): v for k, v in elem.attrib.items()}
        
        # Check for volume references
        if "volume" in tag or "scalarvolume" in tag.lower():
            result["volume_found"] = True
            # Check for storage node reference
            storage_ref = attrib.get("storagenodefref", attrib.get("storagenoderef", ""))
            if storage_ref:
                result["volume_data_file"] = storage_ref
        
        # Check for markup fiducial nodes
        if "markupsfid" in tag.lower() or "fiducial" in tag.lower():
            result["fiducial_nodes"] += 1
            name = attrib.get("name", "")
            
            # Try to get control points info
            fiducial_info = {"name": name, "points": []}
            
            # Look for control points in the element
            for child in elem:
                child_tag = child.tag.lower() if child.tag else ""
                if "controlpoint" in child_tag or "point" in child_tag:
                    pos = child.attrib.get("position", child.attrib.get("pos", ""))
                    if pos:
                        fiducial_info["points"].append(pos)
            
            if name:
                result["fiducials"].append(fiducial_info)
    
    # Also check for data directory with actual files
    data_dir = os.path.join(extract_dir, "Data")
    if os.path.isdir(data_dir):
        files = os.listdir(data_dir)
        for f in files:
            if f.endswith(('.nrrd', '.nii', '.nii.gz', '.mha', '.mhd')):
                result["volume_found"] = True
                result["volume_data_file"] = f
                break
            if f.endswith(('.fcsv', '.json')) and 'fiducial' in f.lower():
                # Try to parse fiducial file
                fpath = os.path.join(data_dir, f)
                try:
                    if f.endswith('.json'):
                        with open(fpath) as jf:
                            fdata = json.load(jf)
                            if 'markups' in fdata:
                                for m in fdata['markups']:
                                    fname = m.get('name', '')
                                    cps = m.get('controlPoints', [])
                                    points = []
                                    for cp in cps:
                                        pos = cp.get('position', [0,0,0])
                                        points.append(pos)
                                    result["fiducials"].append({"name": fname, "points": points})
                except Exception as e:
                    pass
    
    # Output results
    print(f"VOLUME_DATA_BUNDLED={'true' if result['volume_found'] else 'false'}")
    print(f"NUM_FIDUCIALS={len(result['fiducials'])}")
    
    labels = [f['name'] for f in result['fiducials'] if f.get('name')]
    print(f"FIDUCIAL_LABELS={json.dumps(labels)}")
    
    coords = []
    for f in result['fiducials']:
        if f.get('points'):
            coords.append(f['points'])
    print(f"FIDUCIAL_COORDINATES={json.dumps(coords)}")
    
except Exception as e:
    print(f"PARSE_ERROR={str(e)}", file=sys.stderr)
    print("VOLUME_DATA_BUNDLED=false")
    print("NUM_FIDUCIALS=0")
    print("FIDUCIAL_LABELS=[]")
    print("FIDUCIAL_COORDINATES=[]")
PYEOF
            
            # Capture Python output
            PARSE_OUTPUT=$(python3 << PYEOF2
import os
import sys
import json
import xml.etree.ElementTree as ET

mrml_path = "$MRML_FILE"
extract_dir = "$EXTRACT_DIR"

try:
    tree = ET.parse(mrml_path)
    root = tree.getroot()
    
    result = {
        "volume_found": False,
        "volume_data_file": None,
        "fiducials": [],
        "fiducial_labels": [],
        "fiducial_coordinates": []
    }
    
    # Look for volume nodes
    for elem in root.iter():
        tag = elem.tag if elem.tag else ""
        
        if "Volume" in tag or "ScalarVolume" in tag:
            result["volume_found"] = True
        
        if "MarkupsFiducial" in tag or "Fiducial" in tag:
            name = elem.attrib.get("name", elem.attrib.get("Name", ""))
            if name:
                result["fiducial_labels"].append(name)
    
    # Check Data directory for actual files
    data_dir = os.path.join(extract_dir, "Data")
    if os.path.isdir(data_dir):
        files = os.listdir(data_dir)
        for f in files:
            fpath = os.path.join(data_dir, f)
            
            # Check for volume data
            if f.endswith(('.nrrd', '.nii', '.nii.gz', '.mha', '.mhd', '.nhdr')):
                fsize = os.path.getsize(fpath)
                if fsize > 100000:  # >100KB indicates real data
                    result["volume_found"] = True
                    result["volume_data_file"] = f
            
            # Check for fiducial files
            if f.endswith('.mrk.json') or ('Fiducial' in f and f.endswith('.json')):
                try:
                    with open(fpath) as jf:
                        fdata = json.load(jf)
                        if 'markups' in fdata:
                            for m in fdata['markups']:
                                fname = m.get('name', '')
                                if fname and fname not in result["fiducial_labels"]:
                                    result["fiducial_labels"].append(fname)
                                cps = m.get('controlPoints', [])
                                for cp in cps:
                                    pos = cp.get('position', [0,0,0])
                                    result["fiducial_coordinates"].append(pos)
                except:
                    pass
            
            # Also check .fcsv files
            if f.endswith('.fcsv'):
                try:
                    with open(fpath) as ff:
                        for line in ff:
                            if line.startswith('#'):
                                continue
                            parts = line.strip().split(',')
                            if len(parts) >= 4:
                                label = parts[0]
                                if label and label not in result["fiducial_labels"]:
                                    result["fiducial_labels"].append(label)
                                try:
                                    x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
                                    result["fiducial_coordinates"].append([x, y, z])
                                except:
                                    pass
                except:
                    pass
    
    # Output JSON result
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e), "volume_found": False, "fiducial_labels": [], "fiducial_coordinates": []}))
PYEOF2
)
            
            # Parse the output
            if [ -n "$PARSE_OUTPUT" ]; then
                echo "Parse output: $PARSE_OUTPUT"
                
                VOLUME_DATA_BUNDLED=$(echo "$PARSE_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('volume_found',False) else 'false')" 2>/dev/null || echo "false")
                NUM_FIDUCIALS=$(echo "$PARSE_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('fiducial_labels',[])))" 2>/dev/null || echo "0")
                FIDUCIAL_LABELS=$(echo "$PARSE_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('fiducial_labels',[])))" 2>/dev/null || echo "[]")
                FIDUCIAL_COORDINATES=$(echo "$PARSE_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('fiducial_coordinates',[])))" 2>/dev/null || echo "[]")
            fi
        fi
    else
        echo "MRB is NOT a valid ZIP archive"
    fi
    
    # Cleanup
    rm -rf "$EXTRACT_DIR" 2>/dev/null || true
else
    echo "MRB file not found at expected location: $OUTPUT_FILE"
    
    # Search for any .mrb files in common locations
    echo "Searching for MRB files..."
    FOUND_MRB=$(find /home/ga -name "*.mrb" -type f 2>/dev/null | head -3)
    if [ -n "$FOUND_MRB" ]; then
        echo "Found MRB files:"
        echo "$FOUND_MRB"
    fi
fi

# Close Slicer
echo "Closing 3D Slicer..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "mrb_exists": $MRB_EXISTS,
    "mrb_size_bytes": $MRB_SIZE_BYTES,
    "mrb_mtime": $MRB_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "is_valid_zip": $IS_VALID_ZIP,
    "contains_mrml": $CONTAINS_MRML,
    "mrml_filename": "$MRML_FILENAME",
    "volume_data_bundled": $VOLUME_DATA_BUNDLED,
    "num_fiducials": $NUM_FIDUCIALS,
    "fiducial_labels": $FIDUCIAL_LABELS,
    "fiducial_coordinates": $FIDUCIAL_COORDINATES,
    "slicer_was_running": $SLICER_RUNNING,
    "output_path": "$OUTPUT_FILE"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="